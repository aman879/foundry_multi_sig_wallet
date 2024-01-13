// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

contract MultiSignatureWallet {

    // state variable to store contract details
    address private contractOwner;
    address[] private owners;
    uint8 private requiredNumOfApproval;

    // enum to set the state of transaction
    enum State {
        SUBMITTED,
        APPROVED,
        EXECUTED
    }

    // struct data type to store tx details
    struct Transaction {
        address to;
        uint256 value;
        bytes data;
        State state;
        uint8 numOfApproval;
    }

    Transaction[] private transactions;

    mapping(address => bool) public isOwner;  // map owner address to true or false if available
    mapping(uint256 => mapping(address => bool)) private isApprovedByOwner; // tx index => owner => bool

    // event logs
    event Deposit(address indexed sender, uint256 amount, uint256 balance);
    event SubmitTransaction(address indexed owner, uint256 indexed txIndex, address indexed to, uint256 value, bytes data);
    event ApproveTransaction(address indexed owner, uint256 indexed txIndex);
    event RevokeTransaction(address indexed owner, uint256 indexed txIndex);
    event ExecuteTransaction(address indexed owner, uint256 txIndex);

    
    modifier onlyOwner {
        require( isOwner[msg.sender], "You are not eligible");
        _;
    }

    modifier onlyContractOwner {
        require( msg.sender == contractOwner, "Only contract owner can call this");
        _;
    }

    modifier onlyExistingTx(uint256 _txIndex) {
        require( _txIndex < transactions.length, "Invalid transction index");
        _;
    }

    modifier onlyNonExecuted(uint256 _txIndex) {
        require( transactions[_txIndex].state != State.EXECUTED, "Tx executed");
        _;
    }

    constructor(address[] memory _owners, uint8 _requiredNumOfApproval) {
        require( _owners.length > 0, "Please add owner address");
        require( _requiredNumOfApproval > 0 &&
                _requiredNumOfApproval <= _owners.length,
                "Invalid number of confirmation" 
        );

        contractOwner = msg.sender;

        for(uint256 i = 0; i < _owners.length; i++ ) {
            address owner = _owners[i];

            require( owner != address(0), "Invalid owner address");
            require( !isOwner[owner], "Already owner");

            isOwner[owner] = true;
            owners.push(owner);
        }
        requiredNumOfApproval = _requiredNumOfApproval;
    } 

    receive() external payable {
        emit Deposit(msg.sender, msg.value, address(this).balance);
    }

    function submitTransaction(
        address _to,
        uint256 _value,
        bytes memory _data
    ) public onlyOwner {
        uint256 txIndex = transactions.length;

        transactions.push(
            Transaction({
                to: _to,
                value: _value,
                data: _data,
                state: State.SUBMITTED,
                numOfApproval: 0
            })
        );

        emit SubmitTransaction(msg.sender, txIndex, _to, _value, _data);
    }

    function approveTransaction(uint256 _txIndex)
        public
        onlyOwner
        onlyExistingTx(_txIndex)
        onlyNonExecuted(_txIndex) {

            require( !isApprovedByOwner[_txIndex][msg.sender], "You have already aprroved");

            Transaction storage transaction = transactions[_txIndex];
            transaction.state = State.APPROVED;
            transaction.numOfApproval += 1;
            isApprovedByOwner[_txIndex][msg.sender] = true;

            if(transaction.numOfApproval >= requiredNumOfApproval) {
                transaction.state = State.APPROVED;
            }

            emit ApproveTransaction(msg.sender, _txIndex);
    }

    function executeTransaction(uint256 _txIndex)
        public
        onlyOwner
        onlyExistingTx(_txIndex)
        onlyNonExecuted(_txIndex) {

            Transaction storage transaction = transactions[_txIndex];
            require(transaction.state == State.APPROVED, "Transaction havent approved yet");

            transaction.state = State.EXECUTED;

            (bool success,) = transaction.to.call{value: transaction.value}(
                transaction.data
            );

            require(success, "tx failed");

            emit ExecuteTransaction(msg.sender, _txIndex);
    }

    function cancelTransaction(uint256 _txIndex)
        public
        onlyOwner
        onlyExistingTx(_txIndex)
        onlyNonExecuted(_txIndex) {

            Transaction storage transaction = transactions[_txIndex];
            require( isApprovedByOwner[_txIndex][msg.sender], "You didnt approved this tx");

            transaction.numOfApproval -= 1;
            isApprovedByOwner[_txIndex][msg.sender] = false;

            if ( transaction.numOfApproval < requiredNumOfApproval) {
                transaction.state = State.SUBMITTED;
            }

            emit RevokeTransaction(msg.sender, _txIndex);
    }

    function getTransaction(uint256 _txIndex)
        external
        view
        returns(
            address to,
            uint256 value,
            bytes memory data,
            State state,
            uint256 numofApproval
        ) {
            Transaction storage transaction = transactions[_txIndex];

            return(
                transaction.to,
                transaction.value,
                transaction.data,
                transaction.state,
                transaction.numOfApproval
            );
    }

    function getTransactionState(uint256 _txIndex) external view returns(State) {
        return transactions[_txIndex].state;
    }

    function addOwner(address _owner) external onlyContractOwner {
        require(!isOwner[_owner], "Already added");
        require(_owner != address(0), "Invalid owner address");
        
        isOwner[_owner] = true;
        owners.push(_owner);
    }

    function addRequiredNumOfApproval(uint8 _requiredNumOfApproval) external onlyContractOwner {
        requiredNumOfApproval += _requiredNumOfApproval;
    }

    function getOwners() external view returns (address[] memory) {
        return owners;
    }

    function getTotalTransaction() external view returns (uint256) {
        return transactions.length;
    }

    function getRequiredNumOfApproval() external view returns(uint8) {
        return requiredNumOfApproval;
    }

    function getApproveByOwner(uint256 _txIndex, address _owner) external view returns(bool) {
        return isApprovedByOwner[_txIndex][_owner];
    }
}