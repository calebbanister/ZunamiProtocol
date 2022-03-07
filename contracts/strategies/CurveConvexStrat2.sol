//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import '../utils/Constants.sol';
import '../interfaces/ICurvePool.sol';
import '../interfaces/ICurvePool2.sol';
import './CurveConvexExtraStratBase.sol';

contract CurveConvexStrat2 is CurveConvexExtraStratBase {
    using SafeERC20 for IERC20Metadata;

    ICurvePool2 public pool;
    ICurvePool public pool3;
    IERC20Metadata public pool3LP;

    constructor(
        Config memory config,
        address poolAddr,
        address poolLPAddr,
        address rewardsAddr,
        uint256 poolPID,
        address tokenAddr,
        address extraRewardsAddr,
        address extraTokenAddr
    )
        CurveConvexExtraStratBase(
            config,
            poolLPAddr,
            rewardsAddr,
            poolPID,
            tokenAddr,
            extraRewardsAddr,
            extraTokenAddr
        )
    {
        pool = ICurvePool2(poolAddr);

        pool3 = ICurvePool(Constants.CRV_3POOL_ADDRESS);
        pool3LP = IERC20Metadata(Constants.CRV_3POOL_LP_ADDRESS);
    }

    function getCurvePoolPrice() internal view override returns (uint256) {
        return pool.get_virtual_price();
    }

    /**
     * @dev Returns deposited amount in USD.
     * If deposit failed return zero
     * @return Returns deposited amount in USD.
     * @param amounts - amounts in stablecoins that user deposit
     */
    function deposit(uint256[3] memory amounts) external override onlyZunami returns (uint256) {
        uint256 amountsTotal;
        for (uint256 i = 0; i < 3; i++) {
            amountsTotal += amounts[i] * decimalsMultipliers[i];
        }
        uint256 amountsMin = (amountsTotal * minDepositAmount) / DEPOSIT_DENOMINATOR;
        uint256 lpPrice = pool3.get_virtual_price();
        uint256 depositedLp = pool3.calc_token_amount(amounts, true);
        if ((depositedLp * lpPrice) / CURVE_PRICE_DENOMINATOR < amountsMin) {
            return (0);
        }

        for (uint256 i = 0; i < 3; i++) {
            IERC20Metadata(_config.tokens[i]).safeIncreaseAllowance(address(pool3), amounts[i]);
        }
        pool3.add_liquidity(amounts, 0);

        uint256[2] memory amounts2;
        amounts2[1] = pool3LP.balanceOf(address(this));
        pool3LP.safeIncreaseAllowance(address(pool), amounts2[1]);
        uint256 poolLPs = pool.add_liquidity(amounts2, 0);

        poolLP.safeApprove(address(_config.booster), poolLPs);
        _config.booster.depositAll(cvxPoolPID, true);

        return ((poolLPs * pool.get_virtual_price()) / CURVE_PRICE_DENOMINATOR);
    }

    function calcCurveDepositShares(
        WithdrawalType withdrawalType,
        uint256 lpShareUserRation, // multiplied by 1e18
        uint256[3] memory tokenAmounts,
        uint128 tokenIndex
    ) internal view override returns(
        bool success,
        uint256 depositedShare,
        uint[] memory tokenAmountsDynamic
    ) {
        uint256[2] memory minAmounts2;
        minAmounts2[1] = pool3.calc_token_amount(tokenAmounts, false);
        depositedShare = (cvxRewards.balanceOf(address(this)) * lpShareUserRation) /
        1e18;

        success = depositedShare >= pool.calc_token_amount(minAmounts2, false);

        if(success && withdrawalType == WithdrawalType.OneCoin) {
            success = tokenAmounts[tokenIndex] <= pool.calc_withdraw_one_coin(depositedShare, int128(tokenIndex));
        }

        tokenAmountsDynamic = fromArr2(minAmounts2);
    }

    function removeCurveDepositShares(
        uint256 depositedShare,
        uint[] memory tokenAmountsDynamic,
        WithdrawalType withdrawalType,
        uint256[3] memory tokenAmounts,
        uint128 tokenIndex
    ) internal override {
        uint256 prevCrv3Balance = pool3LP.balanceOf(address(this));
        pool.remove_liquidity(depositedShare, toArr2(tokenAmountsDynamic));

        sellToken();

        uint256 crv3LiqAmount = pool3LP.balanceOf(address(this)) - prevCrv3Balance;
        if(withdrawalType == WithdrawalType.Base) {
            pool3.remove_liquidity(crv3LiqAmount, tokenAmounts);
        } else if(withdrawalType == WithdrawalType.Imbalance) {
            pool3.remove_liquidity_imbalance(tokenAmounts, crv3LiqAmount);
        } else if(withdrawalType == WithdrawalType.OneCoin) {
            pool3.remove_liquidity_one_coin(crv3LiqAmount, int128(tokenIndex), tokenAmounts[tokenIndex]);
        }
    }

    /**
     * @dev sell base token on strategy can be called by anyone
     */
    function sellToken() public virtual {
        uint256 sellBal = token.balanceOf(address(this));
        if (sellBal > 0) {
            token.safeApprove(address(pool), sellBal);
            pool.exchange_underlying(0, 3, sellBal, 0);
        }
    }

    function withdrawAllSpecific() internal override {
        uint256[2] memory minAmounts2;
        uint256[3] memory minAmounts;
        pool.remove_liquidity(poolLP.balanceOf(address(this)), minAmounts2);
        sellToken();
        pool3.remove_liquidity(pool3LP.balanceOf(address(this)), minAmounts);
    }
}
