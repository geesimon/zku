pragma solidity >= 0.5.0 <0.7.0;

import "@aztec/protocol/contracts/interfaces/IAZTEC.sol";
import "@aztec/protocol/contracts/libs/NoteUtils.sol";
import "@aztec/protocol/contracts/ERC1724/ZkAsset.sol";
import "./ZKERC20/ZKERC20.sol";
import "./Loan.sol";


/// @Title LoanDapp contract
contract LoanDapp is IAZTEC {
  using NoteUtils for bytes;

  event SettlementCurrencyAdded(
    uint id,
    address settlementAddress
  );

  event LoanApprovedForSettlement(
    address loanId
  );

  event LoanCreated(
    address id,
    address borrower,
    bytes32 notional,
    string borrowerPublicKey,
    uint256[] loanVariables,
    uint createdAt
  );

  event ViewRequestCreated(
    address loanId,
    address lender,
    string lenderPublicKey
  );

  event ViewRequestApproved(
    uint accessId,
    address loanId,
    address user,
    string sharedSecret
  );

  event NoteAccessApproved(
    uint accessId,
    bytes32 note,
    address user,
    string sharedSecret
  );

  address owner = msg.sender;
  address aceAddress;
  address[] public loans;
  mapping(uint => address) public settlementCurrencies;

  uint24 MINT_PRO0F = 66049;
  uint24 BILATERAL_SWAP_PROOF = 65794;

  modifier onlyOwner() {
    require(msg.sender == owner);
    _;
  }

  modifier onlyBorrower(address _loanAddress) {
    Loan loanContract = Loan(_loanAddress);
    require(msg.sender == loanContract.borrower());
    _;
  }

  constructor(address _aceAddress) public {
    aceAddress = _aceAddress;
  }

  /// @dev Retreive registered settlement ZkAsset
  function _getCurrencyContract(uint _settlementCurrencyId) internal view returns (address) {
    require(settlementCurrencies[_settlementCurrencyId] != address(0), 'Settlement Currency is not defined');
    return settlementCurrencies[_settlementCurrencyId];
  }

  function _generateAccessId(bytes32 _note, address _user) internal pure returns (uint) {
    return uint(keccak256(abi.encodePacked(_note, _user)));
  }

  /// @dev Give note access permission to user who knows a shared secret
  function _approveNoteAccess(
    bytes32 _note,
    address _userAddress,
    string memory _sharedSecret
  ) internal {
    uint accessId = _generateAccessId(_note, _userAddress);
    emit NoteAccessApproved(
      accessId,
      _note,
      _userAddress,
      _sharedSecret
    );
  }

  /// @dev Create a loan contract and save to array:loans
  /// @param _notional: loan notional note created by borrower
  /// @param _loanVariables: loan settings
  /// @param _proofData: mint proof used to mint new notes inside the loan’s note registry 
  function _createLoan(
    bytes32 _notional,
    uint256[] memory _loanVariables,
    bytes memory _proofData
  ) private returns (address) {
    address loanCurrency = _getCurrencyContract(_loanVariables[3]);

    Loan newLoan = new Loan(
      _notional,
      _loanVariables,
      msg.sender,
      aceAddress,
      loanCurrency
    );

    loans.push(address(newLoan));
    Loan loanContract = Loan(address(newLoan));

    loanContract.setProofs(1, uint256(-1));
    loanContract.confidentialMint(MINT_PROOF, bytes(_proofData));

    return address(newLoan);
  }

  /// @dev Register supported token as settlment ZkAsset
  function addSettlementCurrency(uint _id, address _address) external onlyOwner {
    settlementCurrencies[_id] = _address;
    emit SettlementCurrencyAdded(_id, _address);
  }

  /// @dev Borrower create a loan
  function createLoan(
    bytes32 _notional,
    string calldata _viewingKey,
    string calldata _borrowerPublicKey,
    uint256[] calldata _loanVariables,
    // [0] interestRate
    // [1] interestPeriod
    // [2] loanDuration
    // [3] settlementCurrencyId
    bytes calldata _proofData
  ) external {
    address loanId = _createLoan(
      _notional,
      _loanVariables,
      _proofData
    );

    emit LoanCreated(
      loanId,
      msg.sender,
      _notional,
      _borrowerPublicKey,
      _loanVariables,
      block.timestamp
    );

    // approve note access by borrower
    _approveNoteAccess(
      _notional,
      msg.sender,
      _viewingKey
    );
  }

  /// @dev Approve spending of loan notional note
  function approveLoanNotional(
    bytes32 _noteHash,
    bytes memory _signature,
    address _loanId
  ) public {
    Loan loanContract = Loan(_loanId);
    loanContract.confidentialApprove(_noteHash, _loanId, true, _signature);
    emit LoanApprovedForSettlement(_loanId);
  }

  /// @dev Request viewing of loan amount
  function submitViewRequest(address _loanId, string calldata _lenderPublicKey) external {
    emit ViewRequestCreated(
      _loanId,
      msg.sender,
      _lenderPublicKey
    );
  }

  /// @dev Give permission for viewing loan amount to lender 
  ///      who owns a shared secret with the borrower
  function approveViewRequest(
    address _loanId,
    address _lender,
    bytes32 _notionalNote,
    string calldata _sharedSecret
  ) external onlyBorrower(_loanId) {
    uint accessId = _generateAccessId(_notionalNote, _lender);

    emit ViewRequestApproved(
      accessId,
      _loanId,
      _lender,
      _sharedSecret
    );
  }

  event SettlementSuccesfull(
    address indexed from,
    address indexed to,
    address loanId,
    uint256 timestamp
  );

  struct LoanPayment {
    address from;
    address to;
    bytes notional;
  }

  mapping(uint => mapping(uint => LoanPayment)) public loanPayments;

  /// @dev Settle loan between borrower and lender
  function settleInitialBalance(
    address _loanId,
    bytes calldata _proofData,
    bytes32 _currentInterestBalance
  ) external {
    Loan loanContract = Loan(_loanId);
    loanContract.settleLoan(_proofData, _currentInterestBalance, msg.sender);
    emit SettlementSuccesfull(
      msg.sender,
      loanContract.borrower(),
      _loanId,
      block.timestamp
    );
  }

  /// @dev Give note access permission to caller who ownes the viewing key
  ///      and a pecified user who know a shared key
  function approveNoteAccess(
    bytes32 _note,
    string calldata _viewingKey,
    string calldata _sharedSecret,
    address _sharedWith
  ) external {
    if (bytes(_viewingKey).length != 0) {
      _approveNoteAccess(
        _note,
        msg.sender,
        _viewingKey
      );
    }

    if (bytes(_sharedSecret).length != 0) {
      _approveNoteAccess(
        _note,
        _sharedWith,
        _sharedSecret
      );
    }
  }
}
