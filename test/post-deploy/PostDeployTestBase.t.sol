// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Test }   from "../../lib/forge-std/src/Test.sol";
import { VmSafe } from "../../lib/forge-std/src/Vm.sol";

/**********************************************************************************************/
/*** Event interfaces (selectors only; mirrors of the component repos' declarations)         ***/
/**********************************************************************************************/

interface IAccessControlEvents {

    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);

}

interface IInitializableEvents {

    event Initialized(uint64 version);

}

interface IPAUFactoryEvents {

    event AccessControlsDeployed(address indexed accessControls);

    event ALMProxyDeployed(address indexed almProxy);

    event ControllerDeployed(
        address indexed controller,
        address         accessControls,
        address         proxy,
        address         rateLimits
    );

    event RateLimitsDeployed(address indexed rateLimits);

}

interface IAdministeredAgentFactoryEvents {

    event AdministeredAgentDeployed(address indexed administeredAgent);

}

interface IAdministeredAgentEvents {

    event AdminAdded(address indexed account, address indexed caller);

}

/**********************************************************************************************/
/*** View interfaces                                                                        ***/
/**********************************************************************************************/

interface IAccessControlLike {

    function hasRole(bytes32 role, address account) external view returns (bool);

}

interface IAccessControlEnumerableLike {

    function getRoleMemberCount(bytes32 role) external view returns (uint256);

}

interface IAdministeredAgentLike {

    function actorCount() external view returns (uint256);

    function adminCount() external view returns (uint256);

    function getAdmin(uint256 index) external view returns (address);

    function getIsAdmin(address account) external view returns (bool);

    function grantorCount() external view returns (uint256);

    function revokerCount() external view returns (uint256);

}

interface IControllerLike {

    // Mirrors diamond-pau's IEnumerableIntegrations records (layout must match for ABI decoding).
    struct Wire {
        bytes4 callSelector;
        bytes4 delegateSelector;
    }

    struct Config {
        address facet;
        Wire[]  wires;
    }

    struct Integration {
        bytes32 id;
        Config  config;
    }

    function accessControls() external view returns (address);

    function beacon() external view returns (address);

    function integrations() external view returns (Integration[] memory);

    function proxy() external view returns (address);

    function rateLimits() external view returns (address);

}

interface IPAUFactoryLike {

    function beacon() external view returns (address);

}

/**
 * @title  PostDeployTestBase
 * @notice Shared helpers for the post-deploy verification tests. Modelled on Spark's
 *         `spark-pau-deploy/test/PostDeployTestBase.t.sol`, with the Etherscan `getLogs` + `curl`
 *         FFI replaced by the native `vm.eth_getLogs` cheatcode against the fork RPC, so no API
 *         key and no `--ffi` are needed.
 *
 *         Everything here reasons about *mined* logs, never about what the deploy script
 *         simulated: the point is to prove that the addresses exported to
 *         `script/output/{chainId}/deploy-pau-latest.json` are the contracts the canonical
 *         factories created for the configured `owner`, and that nothing else has touched them.
 *
 *         Two log sources are supported, selected by `simulate`:
 *           - false: logs are fetched from the chain (`eth_getLogs`) for a real deployment;
 *           - true:  logs are the ones recorded (`vm.recordLogs`) while the deploy script ran
 *                    on the fork inside the test, since those contracts only exist locally.
 */
abstract contract PostDeployTestBase is Test {

    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 internal constant ALLOCATOR_ROLE     = keccak256("ALLOCATOR_ROLE");
    bytes32 internal constant CONTROLLER_ROLE    = keccak256("CONTROLLER");

    /// @dev When true, `_getLogs` reads `recordedLogs` instead of querying the RPC.
    bool internal simulate;

    /// @dev First block scanned by `eth_getLogs` (verify mode only). Defaults to the export's
    ///      `deployBlock`, override via `POSTDEPLOY_FROM_BLOCK`. Logs are always scanned up to
    ///      the fork block, so the window is a few blocks wide and fits RPC block-range caps.
    uint256 internal fromBlock;

    /// @dev Logs captured while the deploy script ran (simulate mode only).
    VmSafe.EthGetLogs[] internal recordedLogs;

    /**********************************************************************************************/
    /*** Log retrieval                                                                          ***/
    /**********************************************************************************************/

    /// @dev Every log ever emitted by `target` up to the fork block.
    function _getLogs(address target) internal returns (VmSafe.EthGetLogs[] memory logs) {
        return _getLogs(target, new bytes32[](0));
    }

    /// @dev Logs emitted by `target` matching `topic0` and `topic1`.
    function _getLogs(address target, bytes32 topic0, bytes32 topic1)
        internal
        returns (VmSafe.EthGetLogs[] memory logs)
    {
        bytes32[] memory topics = new bytes32[](2);
        topics[0] = topic0;
        topics[1] = topic1;

        return _getLogs(target, topics);
    }

    /// @dev Logs emitted by `target` whose leading topics equal `topics` (empty = no filter).
    function _getLogs(address target, bytes32[] memory topics)
        internal
        returns (VmSafe.EthGetLogs[] memory logs)
    {
        if (!simulate) return vm.eth_getLogs(fromBlock, block.number, target, topics);

        uint256 count;

        for (uint256 i = 0; i < recordedLogs.length; i++) {
            if (_matches(recordedLogs[i], target, topics)) count++;
        }

        logs = new VmSafe.EthGetLogs[](count);

        uint256 next;

        for (uint256 i = 0; i < recordedLogs.length; i++) {
            if (_matches(recordedLogs[i], target, topics)) logs[next++] = recordedLogs[i];
        }
    }

    /**
     * @dev Starts recording logs. Call before running the deploy script in simulate mode, then
     *      {_stopRecordingLogs} once it returns.
     */
    function _startRecordingLogs() internal {
        simulate = true;

        delete recordedLogs;

        vm.recordLogs();
    }

    /// @dev Moves the logs recorded since {_startRecordingLogs} into `recordedLogs`.
    function _stopRecordingLogs() internal {
        VmSafe.Log[] memory logs = vm.getRecordedLogs();

        for (uint256 i = 0; i < logs.length; i++) {
            recordedLogs.push(VmSafe.EthGetLogs({
                emitter          : logs[i].emitter,
                topics           : logs[i].topics,
                data             : logs[i].data,
                blockHash        : bytes32(0),
                blockNumber      : uint64(block.number),
                transactionHash  : bytes32(0),
                transactionIndex : uint64(0),
                logIndex         : uint256(0),
                removed          : false
            }));
        }
    }

    function _matches(
        VmSafe.EthGetLogs memory log,
        address                  target,
        bytes32[] memory         topics
    ) internal pure returns (bool) {
        if (log.emitter != target)             return false;
        if (log.topics.length < topics.length) return false;

        for (uint256 i = 0; i < topics.length; i++) {
            if (log.topics[i] != topics[i]) return false;
        }

        return true;
    }

    /**********************************************************************************************/
    /*** Provenance assertions                                                                  ***/
    /**********************************************************************************************/

    /**
     * @dev Asserts that `factory` emitted exactly one `<Component>Deployed(address indexed)`
     *      event (identified by `topic0`) for `child`. For the canonical factories this is the
     *      proof that `child` was created by the factory, at that address, with the factory as
     *      `msg.sender` of the constructor. Returns the log so callers can inspect its data.
     */
    function _assertDeployedByFactory(
        address       factory,
        bytes32       topic0,
        address       child,
        string memory label
    ) internal returns (VmSafe.EthGetLogs memory log) {
        VmSafe.EthGetLogs[] memory logs = _getLogs(factory, topic0, _toBytes32(child));

        assertEq(logs.length, 1, string.concat(label, ": factory Deployed event count"));

        assertEq(logs[0].emitter,               factory, string.concat(label, ": emitter"));
        assertEq(logs[0].topics[0],             topic0,  string.concat(label, ": topic0"));
        assertEq(_toAddress(logs[0].topics[1]), child,   string.concat(label, ": topic1"));

        return logs[0];
    }

    /**********************************************************************************************/
    /*** Event assertions                                                                       ***/
    /**********************************************************************************************/

    /**
     * @dev The full log history of an AccessControl component must be exactly the constructor's
     *      `RoleGranted(DEFAULT_ADMIN_ROLE, owner)` emitted with `factory` as sender. Any extra
     *      grant (another admin) or any revocation fails the test — this is the check the
     *      on-chain init cannot do for the non-enumerable ALMProxy / RateLimits.
     */
    function _assertOnlyConstructorAdminGrant(
        address       target,
        address       owner,
        address       factory,
        string memory label
    ) internal {
        VmSafe.EthGetLogs[] memory logs = _getLogs(target);

        assertEq(logs.length, 1, string.concat(label, ": log count"));

        _assertRoleGrantedEvent(logs[0], DEFAULT_ADMIN_ROLE, owner, factory, label);
    }

    function _assertRoleGrantedEvent(
        VmSafe.EthGetLogs memory log,
        bytes32                  role,
        address                  account,
        address                  sender,
        string memory            label
    ) internal pure {
        assertEq(log.topics.length, 4, string.concat(label, ": RoleGranted topics"));

        assertEq(
            log.topics[0],
            IAccessControlEvents.RoleGranted.selector,
            string.concat(label, ": RoleGranted selector")
        );
        assertEq(log.topics[1],             role,    string.concat(label, ": RoleGranted role"));
        assertEq(_toAddress(log.topics[2]), account, string.concat(label, ": RoleGranted account"));
        assertEq(_toAddress(log.topics[3]), sender,  string.concat(label, ": RoleGranted sender"));
    }

    function _assertInitializedEvent(VmSafe.EthGetLogs memory log, string memory label)
        internal
        pure
    {
        assertEq(log.topics.length, 1, string.concat(label, ": Initialized topics"));

        assertEq(
            log.topics[0],
            IInitializableEvents.Initialized.selector,
            string.concat(label, ": Initialized selector")
        );
        assertEq(log.data, abi.encode(uint64(1)), string.concat(label, ": Initialized version"));
    }

    function _assertAdminAddedEvent(
        VmSafe.EthGetLogs memory log,
        address                  account,
        address                  caller,
        string memory            label
    ) internal pure {
        assertEq(log.topics.length, 3, string.concat(label, ": AdminAdded topics"));

        assertEq(
            log.topics[0],
            IAdministeredAgentEvents.AdminAdded.selector,
            string.concat(label, ": AdminAdded selector")
        );
        assertEq(_toAddress(log.topics[1]), account, string.concat(label, ": AdminAdded account"));
        assertEq(_toAddress(log.topics[2]), caller,  string.concat(label, ": AdminAdded caller"));
    }

    /**********************************************************************************************/
    /*** State assertions                                                                       ***/
    /**********************************************************************************************/

    function _assertAdminState(address target, address owner, string memory label) internal view {
        assertGt(target.code.length, 0, string.concat(label, ": no code"));

        assertTrue(
            IAccessControlLike(target).hasRole(DEFAULT_ADMIN_ROLE, owner),
            string.concat(label, ": owner is not admin")
        );
    }

    function _assertNoControllerRole(address target, address controller, string memory label)
        internal
        view
    {
        assertFalse(
            IAccessControlLike(target).hasRole(CONTROLLER_ROLE, controller),
            string.concat(label, ": CONTROLLER already granted (activation ran?)")
        );
    }

    /**********************************************************************************************/
    /*** Utils                                                                                  ***/
    /**********************************************************************************************/

    function _toAddress(bytes32 b) internal pure returns (address) {
        return address(uint160(uint256(b)));
    }

    function _toBytes32(address a) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(a)));
    }

    function _label(string memory name, uint256 i) internal pure returns (string memory) {
        return string.concat(name, "[", vm.toString(i), "]");
    }

}
