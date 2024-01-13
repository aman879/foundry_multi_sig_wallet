// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import { MultiSignatureWallet } from "../src/MultiSignatureWallet.sol";
import { TestContract } from "../src/TestContract.sol";

contract MultiSignatureWalletTest is Test {
    MultiSignatureWallet public msw;
    TestContract public tc;

    address public contractOwner = vm.addr(1);
    address[] public owners;
    address public testContract;
    bytes public callData;

    enum State {
        SUBMITTED,
        APPROVED,
        EXECUTED
    }

    event SubmitTransaction(address indexed owner, uint256 indexed txIndex, address indexed to, uint256 value, bytes data);
    event ApproveTransaction(address indexed owner, uint256 indexed txIndex);
    event RevokeTransaction(address indexed owner, uint256 indexed txIndex);
    event ExecuteTransaction(address indexed owner, uint256 txIndex);

    function testSetUp() public {
        address[] memory testOwners = new address[](1);
        testOwners[0] = address(0);

        address[] memory testOwners2 = new address[](2);
        testOwners2[0] = address(1);
        testOwners2[1] = address(1);

        vm.startPrank(contractOwner);

        // should revert if address is zero
        vm.expectRevert("Invalid owner address");
        msw = new MultiSignatureWallet(
            testOwners,
            1
        );

        // should revert if provided invalid confirmation number
        vm.expectRevert("Invalid number of confirmation");
        msw = new MultiSignatureWallet(
            testOwners,
            3
        );

        // should revert if provided same address
        vm.expectRevert("Already owner");
        msw = new MultiSignatureWallet(
            testOwners2,
            1
        );

    }

    function setUp() public{
        for(uint256 i = 0; i < 5; i++) {
            owners.push(vm.addr(i + 2));
        }

        vm.prank(contractOwner);
        msw = new MultiSignatureWallet(owners, 3);

        tc = new TestContract();
        testContract = address(tc);
        callData = tc.getData(); 
    }


    // function to test submitTransaction functionality
    function testSubmitTransaction() public {

        // should revert if called by non owner
        vm.expectRevert("You are not eligible");
        msw.submitTransaction(testContract, 0, callData);

        vm.prank(owners[0]);
        // should emit event on succesfull submit of a transaction
        vm.expectEmit(true, true, true, true);
        emit SubmitTransaction(owners[0], 0, testContract, 0, callData);

        msw.submitTransaction(testContract, 0, callData);

        // should update transaction correctly
        ( address to, uint256 value, bytes memory data, , uint256 numOfApproval) = msw.getTransaction(0);
        assertEq(to, testContract);
        assertEq(value, 0);
        assertEq(data, callData);
        assertEq(numOfApproval, 0);
        assertEq(uint8(msw.getTransactionState(0)), uint8(State.SUBMITTED)); 
    }

    // function to test approveTransaction
    function testApproveTransaction() public {

        vm.prank(owners[0]);
        msw.submitTransaction(testContract, 0, callData);

        // should revert if call by non owner
        vm.expectRevert("You are not eligible");
        msw.approveTransaction(0);

        vm.prank(owners[1]);

        // should revert if tx does not exist
        vm.expectRevert("Invalid transction index");
        msw.approveTransaction(2);

        for(uint256 i = 0; i < 3; i++) {
            vm.prank(owners[i]);

            // should emit event after succesfully approving a tx
            vm.expectEmit(true, true, false, true);
            emit ApproveTransaction(owners[i], 0);

            msw.approveTransaction(0);
        }

        // should succesfully change state of transaction
        assertEq(uint8(msw.getTransactionState(0)), uint8(State.APPROVED));

        vm.startPrank(owners[2]);

        // should revert if trying to approve again
        vm.expectRevert("You have already aprroved");
        msw.approveTransaction(0);

        msw.executeTransaction(0);
        // should revert if tx already executed
        vm.expectRevert("Tx executed");
        msw.approveTransaction(0);

        vm.stopPrank();
    }

    // function to test revoke transaction
    function testCancelTransaction() public {
        vm.prank(owners[0]);
        msw.submitTransaction(testContract, 0, callData);

        // should revert if called by non owner
        vm.expectRevert("You are not eligible");
        msw.cancelTransaction(0);

        vm.prank(owners[0]);
        // should revert of txIndex is invalid
        vm.expectRevert("Invalid transction index");
        msw.cancelTransaction(1);

        for(uint256 i = 0; i < 3; i++) {
            vm.prank(owners[i]);
            msw.approveTransaction(0);
        }

        vm.prank(owners[3]);

        // should revert if tx is revoked by owner which didnt approved it
        vm.expectRevert("You didnt approved this tx");
        msw.cancelTransaction(0);

        assertEq(uint8(msw.getTransactionState(0)), uint8(State.APPROVED));

        vm.startPrank(owners[1]);
        // should emit event
        vm.expectEmit(true, true, false, true);
        emit RevokeTransaction(owners[1], 0);
        msw.cancelTransaction(0);

        // should succesfully change the state after revert succesfully
        assertEq(uint8(msw.getTransactionState(0)), uint8(State.SUBMITTED));

        msw.approveTransaction(0);
        msw.executeTransaction(0);

        // should revert if trying to revoke executed tx
        vm.expectRevert("Tx executed");
        msw.cancelTransaction(0);

        vm.stopPrank();
    }

    // function to test execute transaction
    function testExecuteTransaction() public {
        vm.prank(owners[0]);
        msw.submitTransaction(testContract, 0, callData);

        // should revert if called by non owner
        vm.expectRevert("You are not eligible");
        msw.executeTransaction(0);

        vm.prank(owners[0]);
        // should revert of txIndex is invalid
        vm.expectRevert("Invalid transction index");
        msw.executeTransaction(1);

        vm.prank(owners[1]);
        // should revert if executing transaction which havent approved
        vm.expectRevert("Transaction havent approved yet");
        msw.executeTransaction(0);

        for(uint256 i = 0; i < 3; i++) {
            vm.prank(owners[i]);
            msw.approveTransaction(0);
        }

        vm.startPrank(owners[2]);

        // should emit event correctly
        vm.expectEmit(true, true, false, true);
        emit ExecuteTransaction(owners[2], 0);

        // should succesfully execute transaction
        msw.executeTransaction(0);

        // should update the callData correctly
        assertEq(tc.getI(), 123);

        // should change the tx state to EXECUTED
        assertEq(uint8(msw.getTransactionState(0)), uint8(State.EXECUTED));

        // should revert if trying to execute executed tx
        vm.expectRevert("Tx executed");
        msw.executeTransaction(0);

        vm.stopPrank();
    }

    // function to test add owner
    function testAddOwners() public {

        // should revert if not called by contract owner
        vm.prank(owners[0]);
        vm.expectRevert("Only contract owner can call this");
        msw.addOwner(address(1));

        vm.startPrank(contractOwner);

        // should revert of trying to add same owner
        vm.expectRevert("Already added");
        msw.addOwner(owners[2]);

        // should revert if add zero address
        vm.expectRevert("Invalid owner address");
        msw.addOwner(address(0));

        // successfully add owner
        msw.addOwner(address(1));
        assertTrue(msw.isOwner(address(1)));
    }

    // function to test change required number of trnasaction
    function testAddRequiredNumOfApproval() public {
        // should revert if not called by contract owner
        vm.prank(owners[0]);
        vm.expectRevert("Only contract owner can call this");
        msw.addOwner(address(1));

        // should successfully add to required number
        vm.prank(contractOwner);
        msw.addRequiredNumOfApproval(1);

        assertEq(msw.getRequiredNumOfApproval(), 4);

    }

}