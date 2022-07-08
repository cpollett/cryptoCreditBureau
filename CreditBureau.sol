// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

contract CreditBureau {

  address private _notary;

  mapping(address => FicoScore) private _creditScores;

  Loan[] private _availableLoans;

  uint8 private _numLoans;

  //mapping(address => uint) private _realWorldIds;

  constructor() {
    _notary = msg.sender;
  }

  function initScoreLedger(address borrower, uint ficoScore, uint timestamp) public {
    require(msg.sender == _notary, "Only notary can initialize credit score");
    // FIXME: Ensure function can only be called once per address.
    _creditScores[borrower] = FicoScore(ficoScore, timestamp);
  }


  function getScore(address client, uint amountRequested) public view returns (uint) {
    // Version 1, no encryption of scores
    return _creditScores[client].score;

    // FIXME: Use amountRequested
  }

  function updateScoreBorrow(uint amount) public {
    // FIXME: scores should be adapted to FICO range (Chris will fix everything)
      _creditScores[tx.origin].score -= amount;
  }
  function updateScoreRepayment(uint amount) public {
    // FIXME: scores should be adapted to FICO range (Chris will fix everything)
      _creditScores[tx.origin].score += amount;
  }

  function loanPaymentScoreUpdate(address client, address loan, uint amount) public {
    require(msg.sender == loan, "");
  }

  // I'm not totally sure that this function is needed
  /*function addRealEntity(address client, uint ssn) public {
    require(msg.sender == notary,
        "Only credit agency can update ssn");
  }*/

  // The function is payable; the ether passed to the contract
  // will be associated with the loan.
  function createLoan(
      uint totalAmount,
      uint interestRatePerMil,
      uint numPayments,
      uint secondsBetweenPayments,
      uint minCreditScore) public returns (Loan) {
    Loan loan = new Loan(this, totalAmount, interestRatePerMil, numPayments,
        secondsBetweenPayments, minCreditScore);
    _availableLoans.push(loan);
    return loan;
  }

  function getTotalLoanAmount() public view returns (uint) {
    uint total = 0;
    for (uint8 i=0; i<_availableLoans.length; i++) {
      total += _availableLoans[i].getAmount();
    }
    return total;
  }

  function findLoan(uint amountNeeded) public returns (Loan) {
    for (uint8 i=0; i < _availableLoans.length; i++) {
      Loan loan = _availableLoans[i];
      if (loan.getAmount() > amountNeeded) {
        return loan;
      }
    }
    revert("No available loan matches criteria.");
  }

}

contract Loan {
  // borrowers can borrow between 1 wei and total remaining loan amount.
  // lenders can contribute between 1 wei and total remaining amount to fund.
  // We enforce that lenders cannot finish contributing until all borrowers have contributed.
  uint private _amountBorrowed;
  uint private _amountInvested;

  uint private _totalAmount;
  uint private _interestRatePerMil;
  uint private _numPayments;
  uint private _secondsBetweenPayments;

  mapping(address => uint) private _borrower;
  mapping(address => uint) private _borrowerExpectedPayment;
  mapping(address => uint) private _borrowerLastPayment;
  mapping(address => uint) private _remainingOwed;
  mapping(address => uint) private _idealRemainingOwed;

  mapping(address => uint) private _investors;
  mapping(address => uint) private _investorLastWithdraw;

  uint private _minCreditScore;
  uint private _timeLoanStart;

  CreditBureau private _bureau;

  constructor(
      CreditBureau bureau,
      uint totalAmount,
      uint interestRatePerMil,
      uint numPayments,
      uint secondsBetweenPayments,
      uint minCreditScore) {

    _amountInvested = 0;
    _amountBorrowed = 0;

    _bureau = bureau;
    _totalAmount = totalAmount;

    _interestRatePerMil = interestRatePerMil;
    _numPayments = numPayments;
    _secondsBetweenPayments = secondsBetweenPayments;
    _minCreditScore = minCreditScore;
  }

  function getAmount() public view returns (uint) {
    return _totalAmount;
  }

  function borrow(uint amount) public {
    uint creditScore = _bureau.getScore(msg.sender, amount);
    require(creditScore > _minCreditScore, "Insufficient credit score");
    require(_borrower[msg.sender] == 0, "Can't borrow twice");
    require(_amountBorrowed + amount <= _totalAmount, "Not enough ether left to borrow");
    _borrower[msg.sender] = amount;
    uint costOfLoan = calculateInterest(amount, _numPayments) + amount;
    _borrowerExpectedPayment[msg.sender] = costOfLoan / _numPayments;
    _amountBorrowed += amount;
    _bureau.updateScoreBorrow(amount);
    if (isReady()) {
      _timeLoanStart = block.timestamp;
    }
  }

  function invest() public payable {
    // FIXME: Accept partial donation if investor goes over
    require(msg.value + _amountInvested <= _totalAmount, "Exceeds total amount of investment");
    _investors[msg.sender] += msg.value;
    _amountInvested += msg.value;
    if (isReady()) {
      _timeLoanStart = block.timestamp;
    }
  }

  function isReady() public returns (bool) {
    return _totalAmount == _amountInvested && _totalAmount == _amountBorrowed;
  }

  function get$$$() public payable {
    require(isReady(), "Loan is waiting for lenders and borrowers");
    require(_borrower[msg.sender] > 0, "No money allocated for you to borrow");
    uint amount = _borrower[msg.sender];
    _borrower[msg.sender] = 0;
    // FIXME: add interest
    _remainingOwed[msg.sender] = amount;
    payable(msg.sender).transfer(amount);
  }

  function numPaymentsBetweenTimestamps(uint timestamp1, uint timestamp2) public view returns (uint) {
    require(timestamp1 >= timestamp2, "We require the first timestamp to be most recent");
    uint diffTimestamp1Funding = timestamp1 - _timeLoanStart;
    diffTimestamp1Funding = (diffTimestamp1Funding > diffTimestamp1Funding) ? _numPayments : diffTimestamp1Funding;
    uint numTimestamp1PaymentsSinceFunding = diffTimestamp1Funding / _secondsBetweenPayments;
    uint diffTimestamp2Funding = timestamp2 - _timeLoanStart;
    diffTimestamp2Funding = (diffTimestamp2Funding > diffTimestamp2Funding) ? _numPayments : diffTimestamp2Funding;
    uint numTimestamp2PaymentsSinceFunding = diffTimestamp2Funding / _secondsBetweenPayments;
    return numTimestamp1PaymentsSinceFunding - numTimestamp2PaymentsSinceFunding;
  }

  function calculateInterest(uint owed, uint numPayments) public view returns (uint) {
    if (numPayments <= 0) {
      return 0;
    }
    uint secondsPerYear = 365*86400 + 86400/4; //365.25 * seconds/day
    uint ratePerMilPayment = (_interestRatePerMil * _secondsBetweenPayments)/secondsPerYear;
    uint milAugmentInterest = owed * ((1000000 + ratePerMilPayment) ** numPayments);
    uint newAmountOwed = milAugmentInterest / (1000000 ** numPayments);
    return newAmountOwed - owed;
  }

  function makePayment() public payable {
    uint payment = msg.value;
    uint expPayment = _borrowerExpectedPayment[msg.sender];
    uint rOwed = _remainingOwed[msg.sender];
    uint irOwed = _idealRemainingOwed[msg.sender];
    uint numPaymentsSinceLastCalculated = numPaymentsBetweenTimestamps(
      block.timestamp, _borrowerLastPayment[msg.sender]);
    uint interest = calculateInterest(rOwed, numPaymentsSinceLastCalculated);
    uint expInterest = calculateInterest(irOwed, numPaymentsSinceLastCalculated);
    _remainingOwed[msg.sender] = rOwed - payment + interest;
    _idealRemainingOwed[msg.sender] = irOwed - expPayment + expInterest;
    _borrowerLastPayment[msg.sender] = block.timestamp;
    if (_remainingOwed[msg.sender] >= _idealRemainingOwed[msg.sender]) {
      _bureau.updateScoreRepayment(_remainingOwed[msg.sender] -
        _idealRemainingOwed[msg.sender]);
    }
  }

  function withdraw(uint amount) public {
    uint current$$$=address(this).balance;
    require(current$$$ - amount >= 0, "Insufficient funds in the account");
    uint numPaymentsSinceLastCalculated = numPaymentsBetweenTimestamps(
      block.timestamp, _investorLastWithdraw[msg.sender]);
    uint investorBalance = _investors[msg.sender];
    investorBalance = investorBalance + calculateInterest(investorBalance,
      numPaymentsSinceLastCalculated);
    require(investorBalance >= amount, "Withdraw less or equal your investment");
    _investors[msg.sender] = investorBalance - amount;
    _investorLastWithdraw[msg.sender] = block.timestamp;
    payable(msg.sender).transfer(amount);
    /*
       remark: it could be the case that all investors have zero'd out their
       investments and interest is still being paid by the borrowers, in which
       case any remaining money should probably go to the credit bureau (how
       bureau makes money)
     */
  }

  function withdraw(uint amount) public {
    uint current$$$=address(this).balance;   
    require(current$$$ - amount >= 0, "Insufficient funds in the account");
    require(_investors[msg.sender] >= amount, "Withdraw less or equal your investment");  
   //FIXME to include interest rate
    _investors[msg.sender] =  _investors[msg.sender] - amount;
    payable(msg.sender).transfer(amount);
  }

}

struct FicoScore {
    uint score;
    uint timestamp;
}
