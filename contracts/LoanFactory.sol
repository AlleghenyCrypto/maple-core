// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "./Loan.sol";

import "lib/openzeppelin-contracts/contracts/utils/Pausable.sol";

/// @title LoanFactory instantiates Loans.
contract LoanFactory is Pausable {

    using SafeMath for uint256;

    uint8 public constant CL_FACTORY = 0;  // Factory type of `CollateralLockerFactory`
    uint8 public constant FL_FACTORY = 2;  // Factory type of `FundingLockerFactory`

    uint8 public constant INTEREST_CALC_TYPE = 10;  // Calc type of `RepaymentCalc`
    uint8 public constant LATEFEE_CALC_TYPE  = 11;  // Calc type of `LateFeeCalc`
    uint8 public constant PREMIUM_CALC_TYPE  = 12;  // Calc type of `PremiumCalc`

    IGlobals public globals;  // Interface of MapleGlobals

    uint256 public loansCreated;  // Incrementor for number of loan vaults created.

    mapping(uint256 => address) public loans;   // Loans address mapping
    mapping(address => bool)    public isLoan;  // Used to check if a Loan was instantiated from this contract

    mapping(address => bool) public admins;  // Admin addresses that have permission to do certain operations in case of disaster mgt

    event LoanCreated(
        address loan,
        address indexed borrower,
        address indexed liquidityAsset,
        address collateralAsset,
        address collateralLocker,
        address fundingLocker,
        uint256[5] specs,
        address[3] calcs,
        string name,
        string symbol
    );

    constructor(address _globals) public {
        globals = IGlobals(_globals);
    }

    /**
        @dev Update the MapleGlobals contract. Only the Governor can call this function.
        @param newGlobals Address of new MapleGlobals contract
    */
    function setGlobals(address newGlobals) external {
        _isValidGovernor();
        globals = IGlobals(newGlobals);
    }

    /**
        @dev Create a new Loan.
        @param  liquidityAsset  Asset the loan will raise funding in
        @param  collateralAsset Asset the loan will use as collateral
        @param  flFactory       The factory to instantiate a FundingLocker from
        @param  clFactory       The factory to instantiate a CollateralLocker from
        @param  specs           Contains specifications for this loan
                specs[0] = apr
                specs[1] = termDays
                specs[2] = paymentIntervalDays
                specs[3] = requestAmount
                specs[4] = collateralRatio
        @param  calcs The calculators used for the loan.
                calcs[0] = repaymentCalc
                calcs[1] = lateFeeCalc
                calcs[2] = premiumCalc
        @return Address of the instantiated Loan.
    */
    function createLoan(
        address liquidityAsset,
        address collateralAsset,
        address flFactory,
        address clFactory,
        uint256[5] memory specs,
        address[3] memory calcs
    ) external whenNotPaused returns (address) {
        _whenProtocolNotPaused();
        IGlobals _globals = globals;

        // Validity checks
        require(_globals.isValidSubFactory(address(this), flFactory, FL_FACTORY), "LF:INVALID_FL_FACTORY");
        require(_globals.isValidSubFactory(address(this), clFactory, CL_FACTORY), "LF:INVALID_CL_FACTORY");

        require(_globals.isValidCalc(calcs[0], INTEREST_CALC_TYPE), "LF:INVALID_INTEREST_CALC");
        require(_globals.isValidCalc(calcs[1],  LATEFEE_CALC_TYPE), "LF:INVALID_LATE_FEE_CALC");
        require(_globals.isValidCalc(calcs[2],  PREMIUM_CALC_TYPE), "LF:INVALID_PREMIUM_CALC");

        // Deploy new Loan
        Loan loan = new Loan(
            msg.sender,
            liquidityAsset,
            collateralAsset,
            flFactory,
            clFactory,
            specs,
            calcs
        );

        // Update LoanFactory identification mappings
        loans[loansCreated]   = address(loan);
        isLoan[address(loan)] = true;
        loansCreated++;

        emit LoanCreated(
            address(loan),
            msg.sender,
            liquidityAsset,
            collateralAsset,
            loan.collateralLocker(),
            loan.fundingLocker(),
            specs,
            calcs,
            loan.name(),
            loan.symbol()
        );
        return address(loan);
    }

    /**
        @dev Set admin. Only the Governor can call this function.
        @param newAdmin New admin address
        @param allowed  Status of an admin
    */
    function setAdmin(address newAdmin, bool allowed) external {
        _isValidGovernor();
        admins[newAdmin] = allowed;
    }

    /**
        @dev Triggers paused state. Halts functionality for certain functions. Only the Governor or a Loan Factory Admin can call this function.
    */
    function pause() external {
        _isValidGovernorOrAdmin();
        super._pause();
    }

    /**
        @dev Triggers unpaused state. Returns functionality for certain functions. Only the Governor or a Loan Factory Admin can call this function.
    */
    function unpause() external {
        _isValidGovernorOrAdmin();
        super._unpause();
    }

    /**
        @dev Checks that msg.sender is the Governor.
    */
    function _isValidGovernor() internal view {
        require(msg.sender == globals.governor(), "PoolFactory:INVALID_GOVERNOR");
    }

    /**
        @dev Checks that msg.sender is the Governor or a Loan Factory Admin.
    */
    function _isValidGovernorOrAdmin() internal {
        require(msg.sender == globals.governor() || admins[msg.sender], "PoolFactory:UNAUTHORIZED");
    }

    /**
        @dev Function to determine if protocol is paused/unpaused.
    */
    function _whenProtocolNotPaused() internal {
        require(!globals.protocolPaused(), "PoolFactory:PROTOCOL_PAUSED");
    }
}
