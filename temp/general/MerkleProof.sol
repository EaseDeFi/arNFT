
// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

/**
 * @dev These functions deal with verification of Merkle trees (hash trees),
 */
library MerkleProof {
    function calculateRoot(bytes32[] memory leaves) internal pure returns(bytes32) {
        require(leaves.length > 0, "Cannot compute zero length");
        bytes32[] memory elements = leaves;
        bytes32[] memory nextLayer = new bytes32[]((elements.length+1)/2) ;
        while(elements.length > 1) {
            for(uint256 i = 0; i<elements.length;i+=2){
                bytes32 left;
                bytes32 right;
                if(i == elements.length - 1){
                    left = elements[i];
                    right = elements[i];
                }
                else if(elements[i] <= elements[i+1]){
                    left = elements[i];
                    right = elements[i+1];
                }
                else {
                    left = elements[i+1];
                    right = elements[i];
                }
                bytes32 elem = keccak256(abi.encodePacked(left,right));
                nextLayer[i/2] = elem;
            }
            elements = nextLayer;
            nextLayer = new bytes32[]((elements.length+1)/2);
        }
        return elements[0];
    }
    /**
     * @dev Returns true if a `leaf` can be proved to be a part of a Merkle tree
     * defined by `root`. For this, a `proof` must be provided, containing
     * sibling hashes on the branch from the leaf to the root of the tree. Each
     * pair of leaves and each pair of pre-images are assumed to be sorted.
     */
    function verify(bytes32[] memory proof, bytes32 root, bytes32 leaf) internal pure returns (bool) {
        bytes32 computedHash = leaf;

        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];

            if (computedHash <= proofElement) {
                // Hash(current computed hash + current element of the proof)
                computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
            } else {
                // Hash(current element of the proof + current computed hash)
                computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
            }
        }

        // Check if the computed hash (root) is equal to the provided root
        return computedHash == root;
    }
}
