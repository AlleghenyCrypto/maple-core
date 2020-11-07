// SPDX-License-Identifier: MIT

pragma solidity 0.7.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./Token/IFundsDistributionToken.sol";
import "./Token/FundsDistributionToken.sol";

// @title LPStakeLocker is responsbile for escrowing staked assets and distributing a portion of interest payments.
contract LPStakeLocker is IFundsDistributionToken, FundsDistributionToken {
	using SafeMathInt for int256;
	using SignedSafeMath for int256;

	// The primary investment asset for the LP, and the dividend token for this contract.
	IERC20 private ILiquidAsset;
	IERC20 private IStakedAsset;
	// @notice  The amount of LiquidAsset tokens (dividends) currently present and accounted for in this contract.
	uint256 public fundsTokenBalance;

	// @notice The primary investment asset for the liquidity pool. Also the dividend token for this contract.
	address public liquidAsset;

	// @notice The asset deposited by stakers into this contract, for liquidation during defaults.
	address public stakedAsset;

	// TODO: Dynamically assign name and locker to the FundsDistributionToken() params.
	constructor(address _stakedAsset, address _liquidAsset)
		public
		FundsDistributionToken("Maple Stake Locker", "MPLSTAKE")
	{
		liquidAsset = _liquidAsset;
		stakedAsset = _stakedAsset;
		ILiquidAsset = IERC20(_liquidAsset);
		IStakedAsset = IERC20(_stakedAsset);
	}
	/**
	* @notice Deposit stakedAsset and mint an equal number of FundsDistributionTokens to the user
	* @param _amt Amount of stakedAsset(BPTs) to stake
	*/
	function stake(uint256 _amt) external {
		require(
			IStakedAsset.transferFrom(tx.origin, address(this), _amt),
			"LPStakeLocker: ERR_INSUFFICIENT_APPROVED_FUNDS"
		);
		_mint(tx.origin, _amt);
	}

	/**
	 * @notice Withdraws all available funds for a token holder
	 */
	function withdrawFunds() external override {
		uint256 withdrawableFunds = _prepareWithdraw();

		require(
			ILiquidAsset.transfer(msg.sender, withdrawableFunds),
			"FDT_ERC20Extension.withdrawFunds: TRANSFER_FAILED"
		);

		_updateFundsTokenBalance();
	}

	/**
	 * @dev Updates the current funds token balance
	 * and returns the difference of new and previous funds token balances
	 * @return A int256 representing the difference of the new and previous funds token balance
	 */
	function _updateFundsTokenBalance() internal returns (int256) {
		uint256 prevFundsTokenBalance = fundsTokenBalance;

		fundsTokenBalance = ILiquidAsset.balanceOf(address(this));

		return int256(fundsTokenBalance).sub(int256(prevFundsTokenBalance));
	}

	/**
	 * @notice Register a payment of funds in tokens. May be called directly after a deposit is made.
	 * @dev Calls _updateIliquidAssetBalance(), whereby the contract computes the delta of the previous and the new
	 * funds token balance and increments the total received funds (cumulative) by delta by calling _registerFunds()
	 */
}