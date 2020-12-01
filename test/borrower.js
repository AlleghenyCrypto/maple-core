const { expect, assert } = require("chai");
const { BigNumber } = require("ethers");

describe("Borrower Journey", function () {

  let loanVaultAddress;

  it("A - Fetch the list of borrowTokens / collateralTokens", async function () {

    const MapleGlobalsAddress = require("../../contracts/localhost/addresses/MapleGlobals.address");
    const MapleGlobalsABI = require("../../contracts/localhost/abis/MapleGlobals.abi");

    let MapleGlobals;

    MapleGlobals = new ethers.Contract(
      MapleGlobalsAddress,
      MapleGlobalsABI,
      ethers.provider.getSigner(0)
    );

    const List = await MapleGlobals.getValidTokens();

    // These two arrays are related, in order.
    console.log(
      List["_validBorrowTokenSymbols"],
      List["_validBorrowTokenAddresses"]
    )
    
    // These two arrays are related, in order.
    console.log(
      List["_validCollateralTokenSymbols"],
      List["_validCollateralTokenAddresses"]
    )

  });

  it("B - Calculate the total amount owed for supplied params", async function () {

    // NOTE: Import this in your file ... const { BigNumber } = require("ethers");
    // NOTE: Skip to the end of this test to see the two endpoints required to get your values.

    const getNextPaymentAmount = (
      principalOwed, // 500000 = 500,000 DAI
      APR, // 500 = 5%
      repaymentFrequencyDays, // 30 (Monthly), 90 (Quarterly), 180 (Semi-annually), 360 (Annually)
      paymentsRemaining, // (Term / repaymentFrequencyDays) = (90 Days / 30 Days) = 3 Payments Remaining
      interestStructure // 'BULLET' or 'AMORTIZATION'
    ) => {
      if (interestStructure === 'BULLET') {
        let interest = BigNumber.from(principalOwed).mul(APR).mul(repaymentFrequencyDays).div(365).div(10000);
        return paymentsRemaining == 1 ? 
          [interest.add(principalOwed), interest, principalOwed] : [interest, 0, interest];
      }
      else if (interestStructure === 'AMORTIZATION') {
        let interest = BigNumber.from(principalOwed).mul(APR).mul(repaymentFrequencyDays).div(365).div(10000);
        let principal = BigNumber.from(principalOwed).div(paymentsRemaining);
        return [interest.add(principal), interest, principal];
      }
      else {
        throw 'ERROR_INVALID_INTEREST_STRUCTURE';
      }
    }

    const getTotalAmountOwedBullet = (
      principalOwed,
      APR,
      repaymentFrequencyDays,
      paymentsRemaining
    ) => {

      let amountOwed = getNextPaymentAmount(
        principalOwed,
        APR,
        repaymentFrequencyDays,
        paymentsRemaining,
        'BULLET'
      )

      // Recursive implementation, basecases 0 and 1 for _paymentsRemaining.
      if (paymentsRemaining === 0) {
        return 0;
      }
      else if (paymentsRemaining === 1) {
        return amountOwed[0];
      }
      else {
        return amountOwed[0].add(
          getTotalAmountOwedBullet(
            principalOwed,
            APR,
            repaymentFrequencyDays,
            paymentsRemaining - 1,
            'BULLET'
          )
        );
      }

    }

    const getTotalAmountOwedAmortization = (
      principalOwed,
      APR,
      repaymentFrequencyDays,
      paymentsRemaining
    ) => { 

      let amountOwed = getNextPaymentAmount(
        principalOwed,
        APR,
        repaymentFrequencyDays,
        paymentsRemaining,
        'AMORTIZATION'
      )

      // Recursive implementation, basecases 0 and 1 for _paymentsRemaining.
      if (paymentsRemaining === 0) {
        return 0;
      }
      else if (paymentsRemaining === 1) {
        return amountOwed[0];
      }
      else {
        return amountOwed[0].add(
          getTotalAmountOwedAmortization(
            principalOwed - amountOwed[2],
            APR,
            repaymentFrequencyDays,
            paymentsRemaining - 1,
            'AMORTIZATION'
          )
        );
      }

    }

    const getTotalAmountOwed = (
      principalOwed, // a.k.a. "Loan amount", doesn't need to be in wei for info panel
      APR, // 620 = 6.2%
      termLengthDays, // [30,90,180,360,720]
      repaymentFrequencyDays, // [30,90,180,360]
      paymentStructure // 'BULLET' or 'AMORTIZATION' 
    ) => {

      if (termLengthDays % repaymentFrequencyDays != 0) { 
        throw 'ERROR_UNEVEN_TERM_LENGTH_AND_PAYMENT_INTERVAL'
      }

      if (paymentStructure === 'BULLET') {
        return getTotalAmountOwedBullet(
          principalOwed,
          APR,
          repaymentFrequencyDays,
          termLengthDays / repaymentFrequencyDays
        )
      }
      else if (paymentStructure === 'AMORTIZATION') {
        return getTotalAmountOwedAmortization(
          principalOwed,
          APR,
          repaymentFrequencyDays,
          termLengthDays / repaymentFrequencyDays
        )
      }
      else {
        throw 'ERROR_INVALID_INTEREST_STRUCTURE'
      }
      
    }

    const LOAN_AMOUNT = 100000; // 100,000 DAI
    const APR_BIPS = 1250; // 12.50%
    const TERM_DAYS = 180;
    const PAYMENT_INTERVAL_DAYS = 30;

    let exampleBulletTotalOwed = getTotalAmountOwed(
      LOAN_AMOUNT,
      APR_BIPS,
      TERM_DAYS,
      PAYMENT_INTERVAL_DAYS,
      'BULLET'
    )

    let exampleAmortizationTotalOwed = getTotalAmountOwed(
      LOAN_AMOUNT,
      APR_BIPS,
      TERM_DAYS,
      PAYMENT_INTERVAL_DAYS,
      'AMORTIZATION'
    )

    console.log(
      parseInt(exampleBulletTotalOwed["_hex"]),
      parseInt(exampleAmortizationTotalOwed["_hex"])
    )

  });

  it("C - Create a loan through the factory", async function () {

    const LoanVaultFactoryAddress = require("../../contracts/localhost/addresses/LoanVaultFactory.address");
    const LoanVaultFactoryABI = require("../../contracts/localhost/abis/LoanVaultFactory.abi");

    let LoanVaultFactory;

    LoanVaultFactory = new ethers.Contract(
      LoanVaultFactoryAddress,
      LoanVaultFactoryABI,
      ethers.provider.getSigner(0)
    );

    const preIncrementorValue = await LoanVaultFactory.loanVaultsCreated();

    // ERC-20 contracts for tokens
    const DAIAddress = require("../../contracts/localhost/addresses/MintableTokenDAI.address");
    const USDCAddress = require("../../contracts/localhost/addresses/MintableTokenUSDC.address");
    const WETHAddress = require("../../contracts/localhost/addresses/WETH9.address");
    const WBTCAddress = require("../../contracts/localhost/addresses/WBTC.address");
    
    const ERC20ABI = require("../../contracts/localhost/abis/MintableTokenDAI.abi");

    DAI = new ethers.Contract(DAIAddress, ERC20ABI, ethers.provider.getSigner(0));
    USDC = new ethers.Contract(USDCAddress, ERC20ABI, ethers.provider.getSigner(0));
    WETH = new ethers.Contract(WETHAddress, ERC20ABI, ethers.provider.getSigner(0));
    WBTC = new ethers.Contract(WBTCAddress, ERC20ABI, ethers.provider.getSigner(0));

  
    const REQUESTED_ASSET = DAIAddress;
    const COLLATERAL_ASSET = WETHAddress;
    const INTEREST_STRUCTURE = 'BULLET' // 'BULLET' or 'AMORTIZATION'

    const APR_BIPS = 500; // 5%
    const TERM_DAYS = 90;
    const PAYMENT_INTERVAL_DAYS = 30;
    const MIN_RAISE = BigNumber.from(
      10 // Base 10
    ).pow(
      18 // Decimial precision of REQUEST_ASSET (DAI = 18, USDC = 6, WETH = 18, WBTC = 8)
    ).mul(
      1000 // Amount of loan request (1000 = 1,000 DAI)
    );
    const COLLATERAL_BIPS_RATIO = 5000; // 50%
    const FUNDING_PERIOD_DAYS = 7;

    await LoanVaultFactory.createLoanVault(
      REQUESTED_ASSET,
      COLLATERAL_ASSET,
      [
        APR_BIPS, 
        TERM_DAYS, 
        PAYMENT_INTERVAL_DAYS, 
        MIN_RAISE, 
        COLLATERAL_BIPS_RATIO, 
        FUNDING_PERIOD_DAYS
      ],
      ethers.utils.formatBytes32String(INTEREST_STRUCTURE)
    );

    loanVaultAddress = await LoanVaultFactory.getLoanVault(preIncrementorValue);

  });

  it("D - Simulate other users funding the loan", async function () {

    const LoanVaultABI = require("../../contracts/localhost/abis/LoanVault.abi");
    const ERC20ABI = require("../../contracts/localhost/abis/MintableTokenDAI.abi");
    const accounts = await ethers.provider.listAccounts();

    LoanVault = new ethers.Contract(
      loanVaultAddress,
      LoanVaultABI,
      ethers.provider.getSigner(1)
    );

    const REQUEST_ASSET_ADDRESS = await LoanVault.assetRequested();

    RequestedAsset = new ethers.Contract(
      REQUEST_ASSET_ADDRESS,
      ERC20ABI,
      ethers.provider.getSigner(1)
    )

    // Mint tokens to accounts[1]
    await RequestedAsset.mintSpecial(accounts[1], 750);

    // Approve loan vault
    await RequestedAsset.approve(
      loanVaultAddress,
      BigNumber.from(10).pow(18).mul(750)
    )

    // Fund the loan
    await LoanVault.fundLoan(
      BigNumber.from(10).pow(18).mul(750), // Funding amount.
      accounts[1] // Mint loan tokens for this adddress.
    )

  });

  it("E - Fetch important LoanVault information", async function () {

    const LoanVaultABI = require("../../contracts/localhost/abis/LoanVault.abi");
    const ERC20ABI = require("../../contracts/localhost/abis/MintableTokenDAI.abi");
    
    LoanVault = new ethers.Contract(
      loanVaultAddress,
      LoanVaultABI,
      ethers.provider.getSigner(0)
    );

    const REQUEST_ASSET_ADDRESS = await LoanVault.assetRequested();
    
    RequestedAsset = new ethers.Contract(
      REQUEST_ASSET_ADDRESS,
      ERC20ABI,
      ethers.provider.getSigner(1)
    )

    const DECIMAL_PRECISION_REQUEST_ASSET = await RequestedAsset.decimals();

    const FUNDING_LOCKER_BALANCE = await LoanVault.getFundingLockerBalance();
    const MIN_RAISE = await LoanVault.minRaise();
    
    // Percentage of Target
    console.log(
      parseInt(FUNDING_LOCKER_BALANCE["_hex"]) / parseInt(MIN_RAISE["_hex"]) * 100
    )

    // Funding Locker Balance
    console.log(
      parseInt(FUNDING_LOCKER_BALANCE["_hex"]) / 10**DECIMAL_PRECISION_REQUEST_ASSET
    )

    // Min Raise
    console.log(
      parseInt(MIN_RAISE["_hex"]) / 10**DECIMAL_PRECISION_REQUEST_ASSET
    )

  });

});
