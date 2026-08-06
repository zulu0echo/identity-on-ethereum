// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {ProofGateway} from "../src/ProofGateway.sol";

/// Shared loader for the real-proof fixtures produced by
/// script/generate-fixtures.mjs. Tests are skipped (not failed) when the
/// fixtures haven't been generated yet, so `forge test` passes out of the box.
abstract contract ZKFixtureBase is Test {
    using stdJson for string;

    string internal json;
    bool internal hasFixtures;

    // constants mirrored in script/generate-fixtures.mjs
    uint256 constant GATEWAY_SCOPE = 111;
    uint256 constant GATEWAY_MESSAGE = 42;
    uint256 constant POST_REVOKE_SCOPE = 222;
    uint256 constant CAMPAIGN_SCOPE = 12345;
    address constant CLAIMANT_BEEF = address(0xBEEF);
    address constant CLAIMANT_CAFE = address(0xCAFE);

    function _loadFixtures() internal {
        string memory path = string.concat(vm.projectRoot(), "/test/fixtures/semaphore.json");
        hasFixtures = vm.exists(path);
        if (hasFixtures) {
            json = vm.readFile(path);
        }
    }

    /// Call first in every fixture-dependent test.
    function _requireFixtures() internal {
        if (!hasFixtures) {
            emit log("SKIPPED: run `npm run fixtures` to generate real ZK proofs");
            vm.skip(true);
        }
    }

    function _commitments() internal view returns (uint256[] memory) {
        return json.readUintArray(".commitments");
    }

    function _uint(string memory key) internal view returns (uint256) {
        return json.readUint(key);
    }

    function _uints(string memory key) internal view returns (uint256[] memory) {
        return json.readUintArray(key);
    }

    function _proof(string memory key) internal view returns (ProofGateway.Proof memory p) {
        p.merkleTreeDepth = json.readUint(string.concat(key, ".merkleTreeDepth"));
        p.merkleTreeRoot = json.readUint(string.concat(key, ".merkleTreeRoot"));
        p.nullifier = json.readUint(string.concat(key, ".nullifier"));
        p.message = json.readUint(string.concat(key, ".message"));
        p.scope = json.readUint(string.concat(key, ".scope"));
        uint256[] memory pts = json.readUintArray(string.concat(key, ".points"));
        for (uint256 i = 0; i < 8; i++) {
            p.points[i] = pts[i];
        }
    }
}
