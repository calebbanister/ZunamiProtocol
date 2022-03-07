//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IStrategy {
    enum WithdrawalType { Base, OneCoin, Imbalance }

    function deposit(uint256[3] memory amounts) external returns (uint256);

    function withdraw(
        address withdrawer,
        WithdrawalType withdrawalType,
        uint256 lpShareUserRation, // multiplied by 1e18
        uint256[3] memory tokenAmounts,
        uint128 tokenIndex
    ) external returns (bool);

    function withdrawAll() external;

    function totalHoldings() external view returns (uint256);

    function claimManagementFees() external returns (uint256);
}
