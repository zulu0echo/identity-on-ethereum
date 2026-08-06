// Generates real Semaphore v4 Groth16 proofs and writes them as JSON fixtures
// for the Foundry tests (test/fixtures/semaphore.json).
//
// First run downloads the Semaphore snark artifacts (~few MB) automatically.
// Constants here MUST mirror the constants in test/ZKProof.t.sol and
// test/GatedAirdrop.t.sol.
import { writeFileSync, mkdirSync } from "node:fs";
import { Identity, Group, generateProof } from "@semaphore-protocol/core";

// -- constants mirrored in Solidity tests ------------------------------------
const GATEWAY_SCOPE = 111n;
const GATEWAY_MESSAGE = 42n;
const POST_REVOKE_SCOPE = 222n;
const CAMPAIGN_SCOPE = 12345n;
const CLAIMANT_BEEF = 0xbeefn; // address(0xBEEF)
const CLAIMANT_CAFE = 0xcafen; // address(0xCAFE)
// -----------------------------------------------------------------------------

const s = (v) => v.toString();
const proofJson = (p) => ({
  merkleTreeDepth: Number(p.merkleTreeDepth),
  merkleTreeRoot: s(p.merkleTreeRoot),
  nullifier: s(p.nullifier),
  message: s(p.message),
  scope: s(p.scope),
  points: p.points.map(s),
});

// Deterministic credential holders. The commitment is all the issuer ever sees.
const alice = new Identity("alice-secret");
const bob = new Identity("bob-secret");
const carol = new Identity("carol-secret");
const commitments = [alice, bob, carol].map((m) => m.commitment);

// Tree state 0: all three credentials valid.
const group0 = new Group(commitments);
// Siblings needed by the onchain LeanIMT to zero bob's leaf (index 1),
// computed BEFORE the removal.
const removeSiblings = group0.generateMerkleProof(1).siblings;

// Tree state 1: bob revoked.
const group1 = new Group(commitments);
group1.removeMember(1);

console.log("Generating proofs (downloads snark artifacts on first run)...");
const gatewayProof = await generateProof(alice, group0, GATEWAY_MESSAGE, GATEWAY_SCOPE);
const postRevokeProof = await generateProof(alice, group1, GATEWAY_MESSAGE, POST_REVOKE_SCOPE);
const airdropBob = await generateProof(bob, group0, CLAIMANT_BEEF, CAMPAIGN_SCOPE);
const airdropBobSecond = await generateProof(bob, group0, CLAIMANT_CAFE, CAMPAIGN_SCOPE);
const airdropCarol = await generateProof(carol, group0, CLAIMANT_CAFE, CAMPAIGN_SCOPE);

const out = {
  commitments: commitments.map(s),
  root0: s(group0.root),
  root1: s(group1.root),
  removeSiblings: removeSiblings.map(s),
  gatewayProof: proofJson(gatewayProof),
  postRevokeProof: proofJson(postRevokeProof),
  airdropBob: proofJson(airdropBob),
  airdropBobSecond: proofJson(airdropBobSecond),
  airdropCarol: proofJson(airdropCarol),
};

mkdirSync("test/fixtures", { recursive: true });
writeFileSync("test/fixtures/semaphore.json", JSON.stringify(out, null, 2));
console.log("Wrote test/fixtures/semaphore.json");
