// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Test } from "../../lib/forge-std/src/Test.sol";

import {
    AdministeredAgentDeploy,
    AdministeredAgentDeployParams
} from "../../script/dependencies/AdministeredAgentDeploy.sol";

import { PAUDeploy, PAUDeployParams } from "../../script/dependencies/PAUDeploy.sol";

import {
    AdministeredAgentInitParams
} from "../../migrate/pau-administered-agent/deploy/AdministeredAgentInit.sol";

import { PAUInstance } from "../../migrate/diamond-pau/deploy/PAUInit.sol";

import { SpellHarness } from "../utils/SpellHarness.sol";

interface IAccessControlLike {

    function hasRole(bytes32 role, address account) external view returns (bool);

}

interface IAccessControlEnumerableLike {

    function getRoleMemberCount(bytes32 role) external view returns (uint256);

}

interface IALMProxyLike {

    function CONTROLLER() external view returns (bytes32);

}

interface IAdministeredAgentLike {

    function getIsActor(address account) external view returns (bool);

    function getIsAdmin(address account) external view returns (bool);

    function getIsGrantor(address account) external view returns (bool);

    function getIsRevoker(address account) external view returns (bool);

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

interface IRateLimitsLike {

    function CONTROLLER() external view returns (bytes32);

}

/**
 * @notice Fork integration for the deploy-script + init-library path: {PAUDeploy} /
 *         {AdministeredAgentDeploy} run as the deployer against the canonical on-chain
 *         factories, then a {SpellHarness} (standing in for the governance proxy) runs the
 *         component repos' init libraries exactly as a spell action would.
 */
contract PAUDeployAndInit_Fork_Tests is Test {

    address internal constant ADMINISTERED_AGENT_FACTORY = 0x2968c3b5478cF93B70aB1e24255d4EDBBd27a089;
    address internal constant PAU_FACTORY                = 0x69A5d548830AC2A4Ba90A44a2C75BDA71f97fc66;

    bytes32 internal constant ALLOCATOR_ROLE                = keccak256("ALLOCATOR_ROLE");
    bytes32 internal constant DEFAULT_ADMIN_ROLE            = 0x00;
    bytes32 internal constant TRANSFER_ASSET_INTEGRATION_ID = "TRANSFER_ASSET_FACET";

    address internal actor    = makeAddr("actor");
    address internal deployer = makeAddr("deployer");
    address internal grantor  = makeAddr("grantor");
    address internal revoker  = makeAddr("revoker");

    SpellHarness internal governance;

    PAUDeployParams internal params;

    function setUp() external {
        vm.createSelectFork("mainnet", 25270600);

        governance = new SpellHarness();

        params = PAUDeployParams({ pauFactory: PAU_FACTORY, owner: address(governance) });
    }

    /**********************************************************************************************/
    /*** Helpers                                                                                ***/
    /**********************************************************************************************/

    function _deployPAU() internal returns (PAUInstance memory inst) {
        vm.prank(deployer);
        inst = this.deployPAUExternal(params);
    }

    function _deployAgent() internal returns (address agent) {
        vm.prank(deployer);
        agent = this.deployAgentExternal(
            AdministeredAgentDeployParams({
                agentFactory : ADMINISTERED_AGENT_FACTORY,
                owner        : address(governance)
            })
        );
    }

    // External wrappers so the deploy libraries execute in a frame whose msg.sender can be
    // pranked to `deployer`, proving the deployer address ends up with no roles. The returned
    // addresses are packed into the init library's PAUInstance — the same conversion a spell
    // does from the deployment's exported addresses.
    function deployPAUExternal(PAUDeployParams memory p)
        external
        returns (PAUInstance memory inst)
    {
        (inst.accessControls, inst.almProxy, inst.rateLimits, inst.controller) =
            PAUDeploy.deploy(p);

        inst.beacon = IPAUFactoryLike(p.pauFactory).beacon();
    }

    function deployStackExternal(PAUDeployParams memory p, address almProxy)
        external
        returns (PAUInstance memory inst)
    {
        inst.almProxy = almProxy;

        (inst.accessControls, inst.rateLimits, inst.controller) =
            PAUDeploy.deployStack(p, almProxy);

        inst.beacon = IPAUFactoryLike(p.pauFactory).beacon();
    }

    function deployAgentExternal(AdministeredAgentDeployParams memory p)
        external
        returns (address agent)
    {
        agent = AdministeredAgentDeploy.deploy(p);
    }

    /**********************************************************************************************/
    /*** Deploy Tests                                                                           ***/
    /**********************************************************************************************/

    function test_deploy_ownerIsSoleAdmin_deployerHasNothing() external {
        PAUInstance memory inst = _deployPAU();

        address[3] memory components = [inst.accessControls, inst.almProxy, inst.rateLimits];

        for (uint256 i = 0; i < components.length; i++) {
            assertTrue(
                IAccessControlLike(components[i]).hasRole(DEFAULT_ADMIN_ROLE, address(governance)),
                "owner not admin"
            );

            assertFalse(
                IAccessControlLike(components[i]).hasRole(DEFAULT_ADMIN_ROLE, deployer),
                "deployer has admin"
            );
        }

        // Only AccessControls is AccessControlEnumerable — member count asserted there only.
        assertEq(
            IAccessControlEnumerableLike(inst.accessControls).getRoleMemberCount(DEFAULT_ADMIN_ROLE),
            1,
            "owner not sole admin"
        );

        // Constructor wiring is the only wiring performed at deploy time.
        assertEq(IControllerLike(inst.controller).accessControls(), inst.accessControls);
        assertEq(IControllerLike(inst.controller).proxy(),          inst.almProxy);
        assertEq(IControllerLike(inst.controller).beacon(),         inst.beacon);
        assertEq(IControllerLike(inst.controller).rateLimits(),     inst.rateLimits);

        // No mutable configuration has happened yet: the Controller holds no CONTROLLER role.
        assertFalse(
            IAccessControlLike(inst.almProxy).hasRole(
                IALMProxyLike(inst.almProxy).CONTROLLER(),
                inst.controller
            )
        );

        assertFalse(
            IAccessControlLike(inst.rateLimits).hasRole(
                IRateLimitsLike(inst.rateLimits).CONTROLLER(),
                inst.controller
            )
        );
    }

    function test_deploy_agent_ownerIsSoleAdmin() external {
        address agent = _deployAgent();

        assertTrue(IAdministeredAgentLike(agent).getIsAdmin(address(governance)));
        assertFalse(IAdministeredAgentLike(agent).getIsAdmin(deployer));
    }

    /**********************************************************************************************/
    /*** Init Tests                                                                             ***/
    /**********************************************************************************************/

    function test_init_wiresControllerRoles() external {
        PAUInstance memory inst = _deployPAU();

        bytes32[] memory integrationIds = new bytes32[](1);
        integrationIds[0] = TRANSFER_ASSET_INTEGRATION_ID;

        governance.initPAU(inst, integrationIds);

        assertTrue(
            IAccessControlLike(inst.almProxy).hasRole(
                IALMProxyLike(inst.almProxy).CONTROLLER(),
                inst.controller
            )
        );

        assertTrue(
            IAccessControlLike(inst.rateLimits).hasRole(
                IRateLimitsLike(inst.rateLimits).CONTROLLER(),
                inst.controller
            )
        );

        // Check the passed integration ids are actually registered on the Controller,
        // each wired to a facet with code.
        IControllerLike.Integration[] memory integrations =
            IControllerLike(inst.controller).integrations();

        assertEq(integrations.length,      1);
        assertEq(integrations[0].id,       TRANSFER_ASSET_INTEGRATION_ID);
        assertGt(integrations[0].config.facet.code.length, 0);
    }

    function test_init_emptyIntegrationIds_skipsUpdate() external {
        PAUInstance memory inst = _deployPAU();

        governance.initPAU(inst, new bytes32[](0));

        assertTrue(
            IAccessControlLike(inst.almProxy).hasRole(
                IALMProxyLike(inst.almProxy).CONTROLLER(),
                inst.controller
            )
        );

        // Empty ids => no updateIntegrations call => the Controller has no integrations registered.
        assertEq(IControllerLike(inst.controller).integrations().length, 0);
    }

    function test_init_mismatchedRateLimits_reverts() external {
        PAUInstance memory instA = _deployPAU();
        PAUInstance memory instB = _deployPAU();

        instA.rateLimits = instB.rateLimits;

        vm.expectRevert(bytes("PAUInit/controller-rate-limits-mismatch"));
        governance.initPAU(instA, new bytes32[](0));
    }

    function test_init_mismatchedAccessControls_reverts() external {
        PAUInstance memory instA = _deployPAU();
        PAUInstance memory instB = _deployPAU();

        instA.accessControls = instB.accessControls;

        vm.expectRevert(bytes("PAUInit/controller-access-controls-mismatch"));
        governance.initPAU(instA, new bytes32[](0));
    }

    function test_init_mismatchedProxy_reverts() external {
        PAUInstance memory instA = _deployPAU();
        PAUInstance memory instB = _deployPAU();

        instA.almProxy = instB.almProxy;

        vm.expectRevert(bytes("PAUInit/controller-proxy-mismatch"));
        governance.initPAU(instA, new bytes32[](0));
    }

    // Both stacks share the factory's Beacon, so a wrong Beacon must be supplied explicitly.
    function test_init_mismatchedBeacon_reverts() external {
        PAUInstance memory inst = _deployPAU();

        inst.beacon = makeAddr("wrongBeacon");

        vm.expectRevert(bytes("PAUInit/controller-beacon-mismatch"));
        governance.initPAU(inst, new bytes32[](0));
    }

    function test_init_notAdmin_reverts() external {
        // Deployed with a different owner: the harness holds no admin anywhere.
        SpellHarness otherGovernance = new SpellHarness();

        vm.prank(deployer);
        PAUInstance memory inst = this.deployPAUExternal(
            PAUDeployParams({ pauFactory: PAU_FACTORY, owner: address(otherGovernance) })
        );

        vm.expectRevert(bytes("PAUInit/not-access-controls-admin"));
        governance.initPAU(inst, new bytes32[](0));
    }

    /**********************************************************************************************/
    /*** Shared-Proxy Tests                                                                     ***/
    /**********************************************************************************************/

    function test_sharedProxy_twoStacks() external {
        PAUInstance memory instA = _deployPAU();

        vm.prank(deployer);
        PAUInstance memory instB = this.deployStackExternal(params, instA.almProxy);

        assertEq(instB.almProxy, instA.almProxy);

        governance.initPAU(instA, new bytes32[](0));
        governance.initPAU(instB, new bytes32[](0));

        bytes32 controllerRole = IALMProxyLike(instA.almProxy).CONTROLLER();

        // Both Controllers are CONTROLLER on the shared proxy; each only on its own RateLimits.
        assertTrue(IAccessControlLike(instA.almProxy).hasRole(controllerRole, instA.controller));
        assertTrue(IAccessControlLike(instA.almProxy).hasRole(controllerRole, instB.controller));

        assertTrue(
            IAccessControlLike(instA.rateLimits).hasRole(
                IRateLimitsLike(instA.rateLimits).CONTROLLER(),
                instA.controller
            )
        );

        assertFalse(
            IAccessControlLike(instB.rateLimits).hasRole(
                IRateLimitsLike(instB.rateLimits).CONTROLLER(),
                instA.controller
            )
        );
    }

    /**********************************************************************************************/
    /*** Agent Init Tests                                                                       ***/
    /**********************************************************************************************/

    function test_initAgent_configuresRoles_andAllocator() external {
        PAUInstance memory inst = _deployPAU();
        address agent           = _deployAgent();

        governance.initPAU(inst, new bytes32[](0));

        address[] memory actors = new address[](1);
        actors[0] = actor;

        address[] memory grantors = new address[](1);
        grantors[0] = grantor;

        address[] memory revokers = new address[](1);
        revokers[0] = revoker;

        governance.initAgent(agent, AdministeredAgentInitParams({
            admins   : new address[](0),
            actors   : actors,
            grantors : grantors,
            revokers : revokers
        }));

        governance.addAllocator(inst, agent);

        assertTrue(IAdministeredAgentLike(agent).getIsActor(actor));
        assertTrue(IAdministeredAgentLike(agent).getIsGrantor(grantor));
        assertTrue(IAdministeredAgentLike(agent).getIsRevoker(revoker));
        assertTrue(IAdministeredAgentLike(agent).getIsAdmin(address(governance)));

        assertTrue(IAccessControlLike(inst.accessControls).hasRole(ALLOCATOR_ROLE, agent));
    }

    function test_initAgent_zeroActor_reverts() external {
        address agent = _deployAgent();

        address[] memory actors = new address[](1);
        actors[0] = address(0);

        vm.expectRevert(bytes("AdministeredAgentInit/actor-zero-address"));
        governance.initAgent(agent, AdministeredAgentInitParams({
            admins   : new address[](0),
            actors   : actors,
            grantors : new address[](0),
            revokers : new address[](0)
        }));
    }

    function test_initAgent_notAdmin_reverts() external {
        SpellHarness otherGovernance = new SpellHarness();

        vm.prank(deployer);
        address agent = this.deployAgentExternal(
            AdministeredAgentDeployParams({
                agentFactory : ADMINISTERED_AGENT_FACTORY,
                owner        : address(otherGovernance)
            })
        );

        vm.expectRevert(bytes("AdministeredAgentInit/not-admin"));
        governance.initAgent(agent, AdministeredAgentInitParams({
            admins   : new address[](0),
            actors   : new address[](0),
            grantors : new address[](0),
            revokers : new address[](0)
        }));
    }

    function test_addAllocator_zeroAgent_reverts() external {
        PAUInstance memory inst = _deployPAU();

        governance.initPAU(inst, new bytes32[](0));

        vm.expectRevert(bytes("PAUInit/agent-zero-address"));
        governance.addAllocator(inst, address(0));
    }

}
