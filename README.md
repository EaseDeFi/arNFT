# arNFT

arNFT is a non-fungible token built on top of the Nexus Mutual protocol. It enables users to create ERC721 tokens out of cover they purchase through Nexus Mutual. The arNFT contract itself is an ERC721 token with functionality to buy covers, submit claims, and redeem accepted claims from Nexus Mutual. It is based on Yearn’s yNFT and allows users to swap their yNFT tokens for arNFT tokens. It is crucial that an auditor tests the interactions between arNFT and yNFT and arNFT and Nexus Mutual.

# ERC721

arNFT is built with an ERC721 standard that incorporates the base elements, ERC721Enumerable functionality, and ERC721Metadata functionality. The only change made to these contracts (from yNFT and base contracts) is that the total supply counter was removed in exchange for total supply being determined by the allTokens array in ERC721Enumerable (through allTokens.length).

# Nexus Mutual Interactions

The core functionality in arNFT is the ability to buy cover, submit a claim, and redeem a claim through Nexus Mutual.
<br>
<br>    
Basics: arNFT does not store data on its tokens. It stores normal ERC721 data (token IDs, which user they belong to, etc.), but the underlying data is all stored and fetched from the Nexus Mutual contracts themselves. In addition to this, the token ID stored is actually the cover ID on Nexus Mutual. Tokens will not be minted with incremental IDs. This is done in order to save on gas costs.
<br>
<br>
buyCover: arNFT buys cover through Nexus Mutual to protect a user. Our frontend uses Nexus Mutual’s API to get signed data regarding the transaction. We then send this data to our contract, our contract determines whether a user has sent the adequate amount of Ether or tokens to purchase the cover, then we send the data to Nexus Mutual to create and purchase the cover. According to Nexus Mutual, this cover is technically owned by the arNFT contract, so submit claims and redeem claims are all done through that. The cover ID is then determined and saved as the token ID on the arNFT contract.
<br>
<br>
submitClaim: If a hack occurs, an arNFT can then submit a claim to be awarded their coverage through Nexus Mutual. The submit claim function will then call Nexus Mutual if the claim is valid (within the claim expiry time and has not been already submitted) and submit it.

There is functionality in this function to submit a claim through yNFT. Because, even if a user swaps their token, it is still owned by yNFT, submission must be done through their contract. All checks are done within the yNFT contract.
<br>
<br>
redeemClaim: If a claim has been submitted and accepted, a user may redeem their token to receive payment for their coverage. We check to ensure the claim has been accepted, we burn the token so a second redemption cannot occur, then we send the user the assured sum.

This function does not need yNFT routing because of functionality in the Nexus Mutual contracts that will allow yNFT tokens to pay out to the arNFT contract.
<br>
<br>
swapYnft: Simple functionality. transferFroms a yNFT token to arNFT, then mints a user a token using the same cover ID tracking for token ID as other mints. Batch just does this multiple times.
