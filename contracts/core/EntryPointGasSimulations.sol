// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

/* solhint-disable avoid-low-level-calls */
/* solhint-disable no-inline-assembly */

import "./EntryPoint.sol";
import "../interfaces/IEntryPointSimulations.sol";

/*
 * This contract inherits the EntryPoint and extends it with the view-only methods that are executed by
 * the bundler in order to check UserOperation validity and estimate its gas consumption.
 * This contract should never be deployed on-chain and is only used as a parameter for the "eth_call" request.
 */
contract EntryPointGasSimulations is EntryPoint {
    // solhint-disable-next-line var-name-mixedcase
    AggregatorStakeInfo private NOT_AGGREGATED = AggregatorStakeInfo(address(0), StakeInfo(0, 0));

    SenderCreator private _senderCreator;

    function initSenderCreator() internal virtual {
        //this is the address of the first contract created with CREATE by this address.
        address createdObj = address(uint160(uint256(keccak256(abi.encodePacked(hex"d694", address(this), hex"01")))));
        _senderCreator = SenderCreator(createdObj);
    }

    function senderCreator() internal view virtual override returns (SenderCreator) {
        // return the same senderCreator as real EntryPoint.
        // this call is slightly (100) more expensive than EntryPoint's access to immutable member
        return _senderCreator;
    }

    /**
     * simulation contract should not be deployed, and specifically, accounts should not trust
     * it as entrypoint, since the simulation functions don't check the signatures
     */
    constructor() {
        require(block.number < 100, "should not be deployed");
    }

    function estimateGas(
       PackedUserOperation calldata op
    )
    external nonReentrant
    returns (
        GasInfo memory
    ){
        UserOpInfo memory opInfo;
        GasInfo memory gasInfo;
        _simulationOnlyValidations(op);
        _validatePrepayment(0, op, opInfo, gasInfo);
        _executeUserOp(0, op, opInfo, gasInfo);
        return (gasInfo);
    }

    function _simulationOnlyValidations(
        PackedUserOperation calldata userOp
    )
    internal
    {
        //initialize senderCreator(). we can't rely on constructor
        initSenderCreator();

        try
        this._validateSenderAndPaymaster(
            userOp.initCode,
            userOp.sender,
            userOp.paymasterAndData
        )
        // solhint-disable-next-line no-empty-blocks
        {} catch Error(string memory revertReason) {
            if (bytes(revertReason).length != 0) {
                revert FailedOp(0, revertReason);
            }
        }
    }

    /**
     * Called only during simulation.
     * This function always reverts to prevent warm/cold storage differentiation in simulation vs execution.
     * @param initCode         - The smart account constructor code.
     * @param sender           - The sender address.
     * @param paymasterAndData - The paymaster address (followed by other params, ignored by this method)
     */
    function _validateSenderAndPaymaster(
        bytes calldata initCode,
        address sender,
        bytes calldata paymasterAndData
    ) external view {
        if (initCode.length == 0 && sender.code.length == 0) {
            // it would revert anyway. but give a meaningful message
            revert("AA20 account not deployed");
        }
        if (paymasterAndData.length >= 20) {
            address paymaster = address(bytes20(paymasterAndData[0 : 20]));
            if (paymaster.code.length == 0) {
                // It would revert anyway. but give a meaningful message.
                revert("AA30 paymaster not deployed");
            }
        }
        // always revert
        revert("");
    }

    //make sure depositTo cost is more than normal EntryPoint's cost,
    // to mitigate DoS vector on the bundler
    // empiric test showed that without this wrapper, simulation depositTo costs less..
    function depositTo(address account) public override(IStakeManager, StakeManager) payable {
        unchecked{
        // silly code, to waste some gas to make sure depositTo is always little more
        // expensive than on-chain call
            uint256 x = 1;
            while (x < 5) {
                x++;
            }
            StakeManager.depositTo(account);
        }
    }
}
