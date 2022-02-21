//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import '@openzeppelin/contracts/utils/Context.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import '../utils/Constants.sol';

import '../interfaces/IUniswapRouter.sol';
import '../interfaces/IConvexMinter.sol';
import '../interfaces/IZunami.sol';
import '../interfaces/IUniswapV2Pair.sol';
import '../interfaces/IConvexBooster.sol';
import '../interfaces/IConvexRewards.sol';

abstract contract CurveConvexStratBase is Ownable {
    using SafeERC20 for IERC20Metadata;
    using SafeERC20 for IConvexMinter;

    IZunami public zunami;
    IERC20Metadata public crv;
    IConvexMinter public cvx;
    IUniswapRouter public router;
    address public zun;

    uint256 public constant CURVE_USD_MULTIPLIER = 1e12;
    uint256 public constant CURVE_PRICE_DENOMINATOR = 1e18;
    uint256 public minDepositAmount = 9975; // 99.75%
    uint256 public constant DEPOSIT_DENOMINATOR = 10000;
    address public feeDistributor;

    uint256 public usdtPoolId = 2;
    address public usdt;
    uint256 public managementFees = 0;
    uint256 public buybackFee = 0;

    address[] cvxToUsdtPath;
    address[] crvToUsdtPath;
    address[3] public tokens;
    address[] extraTokenSwapPath;

    IERC20Metadata public poolLP;
    IUniswapV2Pair public crvweth;
    IUniswapV2Pair public wethcvx;
    IUniswapV2Pair public wethusdt;
    IConvexBooster public booster;
    IConvexRewards public cvxRewards;
    uint256 public cvxPoolPID;

    uint256[4] public decimalsMultiplierS;

    event SellRewards(uint256 cvxBalance, uint256 crvBalance, uint256 extraBalance);

    /**
     * @dev Throws if called by any account other than the Zunami
     */
    modifier onlyZunami() {
        require(_msgSender() == address(zunami), 'must be called by Zunami contract');
        _;
    }

    constructor(
        address poolLPAddr,
        address rewardsAddr,
        uint256 poolPID
    ) {
        crv = IERC20Metadata(Constants.CRV_ADDRESS);
        cvx = IConvexMinter(Constants.CVX_ADDRESS);
        router = IUniswapRouter(Constants.SUSHI_ROUTER_ADDRESS);
        usdt = Constants.USDT_ADDRESS;
        crvToUsdtPath = [Constants.CRV_ADDRESS, Constants.WETH_ADDRESS, Constants.USDT_ADDRESS];
        cvxToUsdtPath = [Constants.CVX_ADDRESS, Constants.WETH_ADDRESS, Constants.USDT_ADDRESS];

        tokens[0] = Constants.DAI_ADDRESS;
        tokens[1] = Constants.USDC_ADDRESS;
        tokens[2] = Constants.USDT_ADDRESS;
        for (uint256 i; i < 3; i++) {
            decimalsMultiplierS[i] = calcTokenDecimalsMultiplier(IERC20Metadata(tokens[i]));
        }

        crvweth = IUniswapV2Pair(Constants.SUSHI_CRV_WETH_ADDRESS);
        wethcvx = IUniswapV2Pair(Constants.SUSHI_WETH_CVX_ADDRESS);
        wethusdt = IUniswapV2Pair(Constants.SUSHI_WETH_USDT_ADDRESS);
        booster = IConvexBooster(Constants.CVX_BOOSTER_ADDRESS);

        cvxPoolPID = poolPID;
        poolLP = IERC20Metadata(poolLPAddr);
        cvxRewards = IConvexRewards(rewardsAddr);
        feeDistributor = _msgSender();
    }

    function calcTokenDecimalsMultiplier(IERC20Metadata token) internal view returns (uint256) {
        uint8 decimals = token.decimals();
        require(decimals <= 18, 'Zunami: wrong token decimals');
        if (decimals == 18) return 1;
        return 10**(18 - decimals);
    }

    /**
     * @dev anyone can sell rewards, func do nothing if crv&cvx balance is zero
     */
    function sellCrvCvx() public virtual {
        uint256 cvxBalance = cvx.balanceOf(address(this));
        uint256 crvBalance = crv.balanceOf(address(this));
        if (cvxBalance == 0 || crvBalance == 0) {
            return;
        }
        cvx.safeApprove(address(router), cvxBalance);
        crv.safeApprove(address(router), crvBalance);

        uint256 usdtBalanceBefore = IERC20Metadata(usdt).balanceOf(address(this));

        router.swapExactTokensForTokens(
            cvxBalance,
            0,
            cvxToUsdtPath,
            address(this),
            block.timestamp + Constants.TRADE_DEADLINE
        );

        router.swapExactTokensForTokens(
            crvBalance,
            0,
            crvToUsdtPath,
            address(this),
            block.timestamp + Constants.TRADE_DEADLINE
        );

        uint256 usdtBalanceAfter = IERC20Metadata(usdt).balanceOf(address(this));

        managementFees += zunami.calcManagementFee(usdtBalanceAfter - usdtBalanceBefore);
        emit SellRewards(cvxBalance, crvBalance, 0);
    }

    /**
     * @dev Returns total USD holdings in strategy.
     * return amount is lpBalance x lpPrice + cvx x cvxPrice + crv * crvPrice.
     * @return Returns total USD holdings in strategy
     */
    function totalHoldings() public view virtual returns (uint256) {
        uint256 crvLpHoldings = (cvxRewards.balanceOf(address(this)) * getCurvePoolPrice()) /
            CURVE_PRICE_DENOMINATOR;

        uint256 crvEarned = cvxRewards.earned(address(this));

        uint256 cvxTotalCliffs = cvx.totalCliffs();
        uint256 cvxRemainCliffs = cvxTotalCliffs - cvx.totalSupply() / cvx.reductionPerCliff();

        uint256 amountIn = (crvEarned * cvxRemainCliffs) /
            cvxTotalCliffs +
            cvx.balanceOf(address(this));
        uint256 cvxEarnings = priceTokenByUniswap(amountIn, cvxToUsdtPath);

        amountIn = crvEarned + crv.balanceOf(address(this));
        uint256 crvEarnings = priceTokenByUniswap(amountIn, crvToUsdtPath);

        uint256 tokensHoldings = 0;
        for (uint256 i = 0; i < 3; i++) {
            tokensHoldings +=
                IERC20Metadata(tokens[i]).balanceOf(address(this)) *
                decimalsMultiplierS[i];
        }

        return tokensHoldings + crvLpHoldings + (cvxEarnings + crvEarnings) * CURVE_USD_MULTIPLIER;
    }

    function priceTokenByUniswap(uint256 amountIn, address[] memory uniswapPath)
        internal
        view
        returns (uint256)
    {
        if (amountIn == 0) return 0;
        uint256[] memory amounts = router.getAmountsOut(amountIn, uniswapPath);
        return amounts[amounts.length - 1];
    }

    function getCurvePoolPrice() internal view virtual returns (uint256);

    /**
     * @dev dev claim managementFees from strategy.
     * zunBuybackAmount goes to buyback ZUN token if buybackFee > 0 && ZUN address not a zero.
     * adminFeeAmount is amount for transfer to dev or governance.
     * when tx completed managementFees = 0
     */
    function claimManagementFees() public {
        uint256 stratBalance = IERC20Metadata(usdt).balanceOf(address(this));
        uint256 transferBalance = managementFees > stratBalance ? stratBalance : managementFees;
        if (transferBalance > 0) {
            IERC20Metadata(usdt).safeTransfer(feeDistributor, transferBalance);
        }
        managementFees = 0;
    }

    /**
     * @dev dev can update buybackFee but it can't be higher than DEPOSIT_DENOMINATOR (100%)
     * if buybackFee > 0 activate ZUN token buyback in claimManagementFees
     * @param _buybackFee - number min amount 0, max amount DEPOSIT_DENOMINATOR
     */
    function updateBuybackFee(uint256 _buybackFee) public onlyOwner {
        require(_buybackFee <= DEPOSIT_DENOMINATOR, 'Wrong amount!');
        buybackFee = _buybackFee;
    }

    /**
     * @dev dev set ZUN token for buyback
     * @param  _zun - address of Zun token (for buyback)
     */
    function setZunToken(address _zun) public onlyOwner {
        zun = _zun;
    }

    /**
     * @dev dev can update minDepositAmount but it can't be higher than 10000 (100%)
     * If user send deposit tx and get deposit amount lower than minDepositAmount than deposit tx failed
     * @param _minDepositAmount - amount which must be the minimum (%) after the deposit, min amount 1, max amount 10000
     */
    function updateMinDepositAmount(uint256 _minDepositAmount) public onlyOwner {
        require(_minDepositAmount > 0 && _minDepositAmount <= 10000, 'Wrong amount!');
        minDepositAmount = _minDepositAmount;
    }

    /**
     * @dev disable renounceOwnership for safety
     */
    function renounceOwnership() public view override onlyOwner {
        revert('The strategy must have an owner');
    }

    /**
     * @dev dev set Zunami (main contract) address
     * @param zunamiAddr - address of main contract (Zunami)
     */
    function setZunami(address zunamiAddr) external onlyOwner {
        zunami = IZunami(zunamiAddr);
    }

    /**
     * @dev governance can withdraw all stuck funds in emergency case
     * @param _token - IERC20Metadata token that should be fully withdraw from Strategy
     */
    function withdrawStuckToken(IERC20Metadata _token) external onlyOwner {
        uint256 tokenBalance = _token.balanceOf(address(this));
        _token.safeTransfer(_msgSender(), tokenBalance);
    }

    /**
     * @dev governance can set feeDistributor address for distribute protocol fees
     * @param _feeDistributor - address feeDistributor that be used for claim fees
     */
    function changeFeeDistributor(address _feeDistributor) external onlyOwner {
        feeDistributor = _feeDistributor;
    }
}
