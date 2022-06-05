// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

contract CreditBureau {

  address private notary;

  mapping(address => FicoScore) private creditScores;

  Loan[] private availableLoans;

  uint8 private numLoans;

  //mapping(address => uint) private realWorldIds;

  constructor() {
    notary = msg.sender;
  }

  function initScoreLedger(address borrower, uint ficoScore, uint timestamp) public {
    require(msg.sender == notary, "Only notary can initialize credit score");
    // FIXME: Ensure function can only be called once per address.
    creditScores[borrower] = FicoScore(ficoScore, timestamp);
  }


  function getScore(address client) public view returns (uint) {
    // Version 1, no encryption of scores
    return creditScores[client].score;
  }

  function updateScore(address client, bytes32 stuff) public {
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
  function createLoan(uint interestRatePerMil) public payable returns (Loan) {
    Loan loan = new Loan(msg.value);
    availableLoans.push(loan);
    return loan;
  }

  function getTotalLoanAmount() public view returns (uint) {
    uint total = 0;
    for (uint8 i=0; i<availableLoans.length; i++) {
      total += availableLoans[i].getAmount();
    }
    return total;
  }

  function findLoan(uint amountNeeded) public returns (Loan) {
    for (uint8 i=0; i<availableLoans.length; i++) {
      Loan loan = availableLoans[i];
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
  uint private _amount;
  uint private _totalAmount;
  uint private _interestRatePerMil;
  uint private _numPayments;
  uint private _secondsBetweenPayments;
  address[] private _borrowers;
  address [] private _investors;
  uint private _minCreditScore;
  uint private _minNumberBorrowers;

  constructor(uint amount) {
    _amount = amount;
  }

  function getAmount() public view returns (uint) {
    return _amount;
  }

  function borrow() public {}

  function invest() public payable {
  } 

  function distributeLoans() public {}

  function makePayment() public payable {
    // Call loanRepaymentUpdateScore
  }

  function withdraw() public {}
}

struct FicoScore {
    uint score;
    uint timestamp;
}

