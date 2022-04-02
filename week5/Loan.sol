pragma solidity >= 0.5.0 <0.7.0;
import "@aztec/protocol/contracts/ERC1724/ZkAssetMintable.sol";
import "@aztec/protocol/contracts/libs/NoteUtils.sol";
import "@aztec/protocol/contracts/interfaces/IZkAsset.sol";
import "./LoanUtilities.sol";


/// @Title Loan contract 
contract Loan is ZkAssetMintable {

  using SafeMath for uint256;
  using NoteUtils for bytes;
  using LoanUtilities for LoanUtilities.LoanVariables;
  LoanUtilities.LoanVariables public loanVariables;


  // Settlement ZKAsset handle value transfer
  IZkAsset public settlementToken;
  // [0] interestRate
  // [1] interestPeriod
  // [2] duration
  // [3] settlementCurrencyId
  // [4] loanSettlementDate
  // [5] lastInterestPaymentDate address public borrower;
  address public lender;
  address public borrower;

  mapping(address => bytes) lenderApprovals;

  event LoanPayment(string paymentType, uint256 lastInterestPaymentDate);
  event LoanDefault();
  event LoanRepaid();

  // AZTec Note
  struct Note {
    address owner;
    bytes32 noteHash;
  }

  function _noteCoderToStruct(bytes memory note) internal pure returns (Note memory codedNote) {
      (address owner, bytes32 noteHash,) = note.extractNote();
      return Note(owner, noteHash );
  }


  // Construct a loan contract and store loan settings
  constructor(
    bytes32 _notional,
    uint256[] memory _loanVariables,
    address _borrower,
    address _aceAddress,
    address _settlementCurrency
   ) public ZkAssetMintable(_aceAddress, address(0), 1, true, false) {
      loanVariables.loanFactory = msg.sender;
      loanVariables.notional = _notional;
      loanVariables.id = address(this);
      loanVariables.interestRate = _loanVariables[0];
      loanVariables.interestPeriod = _loanVariables[1];
      loanVariables.duration = _loanVariables[2];
      loanVariables.borrower = _borrower;
      borrower = _borrower;
      loanVariables.settlementToken = IZkAsset(_settlementCurrency);
      loanVariables.aceAddress = _aceAddress;
  }

  /// @dev Request permission to view the loan
  function requestAccess() public {
    lenderApprovals[msg.sender] = '0x';
  }

  /// @dev Approves lender loan view request
  function approveAccess(address _lender, bytes memory _sharedSecret) public {
    lenderApprovals[_lender] = _sharedSecret;
  }

  /// @dev Settle loan by validating proof and updating note registry
  function settleLoan(
    bytes calldata _proofData,
    bytes32 _currentInterestBalance,
    address _lender
  ) external {
    // Only loan aApp can settle the loan
    LoanUtilities.onlyLoanDapp(msg.sender, loanVariables.loanFactory);

    // Validate loan settlement bilateralSwap proof.
    // The proof outputs are used to update the retrospective note registries.
    // This will destroy the takerBid note and create the makerAsk note in the settlement ZkAsset note registry,
    // and destroy the makerBid note and create the takerAsk note in the loan ZkAsset note registry.
    LoanUtilities._processLoanSettlement(_proofData, loanVariables);

    // Store timestamp to calculate accrued interest 
    loanVariables.loanSettlementDate = block.timestamp;
    loanVariables.lastInterestPaymentDate = block.timestamp;
    loanVariables.currentInterestBalance = _currentInterestBalance;
    loanVariables.lender = _lender;
    lender = _lender;
  }

  /// @dev Create loan note in loan ZkAsset note registry.
  /// @param _proof:  proof that the loan notional note is created by client correctly
  function confidentialMint(uint24 _proof, bytes calldata _proofData) external {
    // Only loan aApp can mint the loan note
    LoanUtilities.onlyLoanDapp(msg.sender, loanVariables.loanFactory);
    require(msg.sender == owner, "only owner can call the confidentialMint() method");
    require(_proofData.length != 0, "proof invalid");
    // overide this function to change the mint method to msg.sender
    (bytes memory _proofOutputs) = ace.mint(_proof, _proofData, msg.sender);

    (, bytes memory newTotal, ,) = _proofOutputs.get(0).extractProofOutput();

    (, bytes memory mintedNotes, ,) = _proofOutputs.get(1).extractProofOutput();

    (,
    bytes32 noteHash,
    bytes memory metadata) = newTotal.extractNote();

    logOutputNotes(mintedNotes);
    emit UpdateTotalMinted(noteHash, metadata);
  }

  /// @dev Lender withdraw interest 
  /// @param _proof1: DIVIDEND_PROOF that proves accrued interest is calculated correctly
  /// @param _proof1: JOIN_SPLIT_PROOF that proves interest note join-split operation is done correctly
  function withdrawInterest(
    bytes memory _proof1,
    bytes memory _proof2,
    uint256 _interestDurationToWithdraw
  ) public {
    (,bytes memory _proof1OutputNotes) = LoanUtilities._validateInterestProof(_proof1, _interestDurationToWithdraw, loanVariables);

    require(_interestDurationToWithdraw.add(loanVariables.lastInterestPaymentDate) < block.timestamp, ' withdraw is greater than accrued interest');

    (bytes32 newCurrentInterestNoteHash) = LoanUtilities._processInterestWithdrawal(_proof2, _proof1OutputNotes, loanVariables);

    // update interest note and subtotal of interest that has been withdrew
    loanVariables.currentInterestBalance = newCurrentInterestNoteHash;
    loanVariables.lastInterestPaymentDate = loanVariables.lastInterestPaymentDate.add(_interestDurationToWithdraw);

    emit LoanPayment('INTEREST', loanVariables.lastInterestPaymentDate);

  }

  /// @dev Borrower pay interest
  /// @param _proofData: JOIN_SPLIT_PROOF that proves interest note join-split operation is done correctly
  function adjustInterestBalance(bytes memory _proofData) public {

    LoanUtilities.onlyBorrower(msg.sender,borrower);

    (bytes32 newCurrentInterestBalance) = LoanUtilities._processAdjustInterest(_proofData, loanVariables);
    // // update interest note after paying the interest
    loanVariables.currentInterestBalance = newCurrentInterestBalance;
  }

  /// @dev Borrower repay loan
  /// @param _proof1: DIVIDEND_PROOF that proves accrued interest plus remaining interest is calculated correctly
  /// @param _proof2: JOIN_SPLIT_PROOF that interest note join-split operation is done correctly
  function repayLoan(
    bytes memory _proof1,
    bytes memory _proof2
  ) public {
    LoanUtilities.onlyBorrower(msg.sender, borrower);

    uint256 remainingInterestDuration = loanVariables.loanSettlementDate.add(loanVariables.duration).sub(loanVariables.lastInterestPaymentDate);

    // validate: repayment == accrued interest + remaining interest
    (,bytes memory _proof1OutputNotes) = LoanUtilities._validateInterestProof(_proof1, remainingInterestDuration, loanVariables);

    require(loanVariables.loanSettlementDate.add(loanVariables.duration) < block.timestamp, 'loan has not matured');

    // make the payment
    LoanUtilities._processLoanRepayment(
      _proof2,
      _proof1OutputNotes,
      loanVariables
    );

    emit LoanRepaid();
  }

  /// @dev Lender mark default of the loan if the interest account has less 
  ///      fund than the (expected) accrued interest
  /// @param _proof1: DIVIDEND_PROOF that proves accrued interest plus remaining interest is calculated correctly
  /// @param _proof2: PRIVATE_RANGE_PROOF that proves the accrued interest is greater than the
  ///                 available balance inside the interest account.
  function markLoanAsDefault(bytes memory _proof1, bytes memory _proof2, uint256 _interestDurationToWithdraw) public {
    require(_interestDurationToWithdraw.add(loanVariables.lastInterestPaymentDate) < block.timestamp, 'withdraw is greater than accrued interest');
    LoanUtilities._validateDefaultProofs(_proof1, _proof2, _interestDurationToWithdraw, loanVariables);
    emit LoanDefault();
  }
}
