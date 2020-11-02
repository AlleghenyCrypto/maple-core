pragma solidity ^0.7.0;

import "../Token/IFundsDistributionToken.sol";
import "../Token/FundsDistributionToken.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ILPStakeLockerFactory {
    function newLocker(address _stakedAsset, address _liquidAsset)
        external
        returns (address);
}

interface IMapleGlobals {
    function mapleToken() external view returns (address);
}

interface IBpool {
    function isFinalized() external view returns (bool);

    function isBound(address) external view returns (bool);

    function getNumTokens() external view returns (uint256);
}

interface ILPStakeocker {
    function stake(uint256 _amountStakedAsset) external returns (uint256);

    function unstake(uint256 _amountStakedAsset) external returns (uint256);

    function withdrawUnstaked(uint256 _amountUnstaked)
        external
        returns (uint256);

    function withdrawInterest() external returns (uint256);
}

contract LP is IFundsDistributionToken, FundsDistributionToken {
    using SafeMathInt for int256;
    using SignedSafeMath for int256;

    // token in which the funds/dividends can be sent for the FundsDistributionToken
    IERC20 private ILiquidAsset;
    ILPStakeLockerFactory private ILockerFactory;
    IERC20 private IStakedAsset;
    ILPStakeocker private IStakedAssetLocker;
    IMapleGlobals private MapleGlobals;
    // balance of fundsToken that the FundsDistributionToken currently holds
    uint256 public fundsTokenBalance;

    // Instantiated during constructor()
    uint256 public stakerFeeBasisPoints;
    uint256 public ongoingFeeBasisPoints;
    address public liquidAsset;
    address public stakedAsset;
    address[] public stakedAssetLockers; //supports 8 for fixed memory
    address public poolDelegate;

    constructor(
        address _liquidAsset,
        address _stakedAsset,
        address _stakedAssetLockerFactory,
        string memory name,
        string memory symbol,
        address _MapleGlobalsaddy
    )
        public

        FundsDistributionToken(name, symbol)
    {
        require(
            address(_liquidAsset) != address(0),
            "FDT_ERC20Extension: INVALID_FUNDS_TOKEN_ADDRESS"
        );

        // address
        liquidAsset = _liquidAsset;
        stakedAsset = _stakedAsset;
        ILiquidAsset = IERC20(_liquidAsset);
        ILockerFactory = ILPStakeLockerFactory(_stakedAssetLockerFactory);
        MapleGlobals = IMapleGlobals(_MapleGlobalsaddy);
        addStakeLocker(_stakedAsset);
    }

    function newStakeLocker(address _stakedAsset)
        private
        returns (address _stakedAssetLocker)
    {
        _stakedAssetLocker = ILockerFactory.newLocker(
            _stakedAsset,
            liquidAsset
        );
    }

    function addStakeLocker(address _stakedAsset) public {
        require(
            IBpool(_stakedAsset).isBound(MapleGlobals.mapleToken()) &&
                IBpool(_stakedAsset).isBound(liquidAsset) &&
                IBpool(_stakedAsset).isFinalized() &&
                (IBpool(_stakedAsset).getNumTokens() == 2),
            "FDT_LP.addStakeLocker: BALANCER_POOL_NOT_ELIDGEABLE"
        );
        stakedAssetLockers.push(newStakeLocker(_stakedAsset));
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

        _updateILiquidAssetBalance();
    }

    /**
     * @dev Updates the current funds token balance
     * and returns the difference of new and previous funds token balances
     * @return A int256 representing the difference of the new and previous funds token balance
     */
    function _updateILiquidAssetBalance() internal returns (int256) {
        uint256 prevILiquidAssetBalance = fundsTokenBalance;

        fundsTokenBalance = ILiquidAsset.balanceOf(address(this));

        return int256(fundsTokenBalance).sub(int256(prevILiquidAssetBalance));
    }

    /**
     * @notice Register a payment of funds in tokens. May be called directly after a deposit is made.
     * @dev Calls _updateILiquidAssetBalance(), whereby the contract computes the delta of the previous and the new
     * funds token balance and increments the total received funds (cumulative) by delta by calling _registerFunds()
     */
    function updateFundsReceived() external {
        int256 newFunds = _updateILiquidAssetBalance();

        if (newFunds > 0) {
            _distributeFunds(newFunds.toUint256Safe());
        }
    }
}
