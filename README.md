**Introduction to Feds**

Feds are smart contracts used to provide Dola liquidity to various other protocols. Dola is minted into a protocol, after which there must be a reasonable expectation, that the Dola can be pulled out of the same protocol in the future.

A privileged, ideally trust minimized role known as the *Fed Chair* controls market actions taken through feds. The main job of the *Fed Chair* is to defend the Dola peg. This means expanding supply when the peg is above 1$ and contracting supply when the peg is below 1$.

The *Fed Chair* of each Fed contract is appointed by Inverse DAO on-chain governance. Inverse DAO governance is also responsible for approving or revoking Dola minting rights of Fed contracts. Some Fed contracts have additional security parameters aimed at restricting the actions of the *Fed Chair*, which are controlled by on-chain DAO governance as well.  

Inverse have historically used two different kinds of Feds: *AMM Feds* and *Lending Market Feds*.

**Lending Market Feds**

Lending market Feds are the first type of Fed developed by Inverse Finance. They supply Dola liquidity into lending markets, either operated by Inverse Finance, such as Frontier,  or third parties, such as Rari Fuse.

*Fed Chairs* expand Dola supply by providing more liquidity to the lending markets, there by lowering rates and encouraging borrowers to short Dola. This has negative impact on Dola price.
The opposite can be done to contract supply, by withdrawing liquidity and burning it, thereby increasing variable rates, and encouraging borrowers to buy Dola and pay back their loans. This has a positive impact on Dola price.

There are currently no active *Lending Market Feds*.

**AMM Feds**

AMM Feds are the second type of Fed developed by Inverse Finance. They supply Dola liquidity directly into AMMs, selling Dola in return for whichever other token makes up the trading pair. Such Feds make the assumption that the paired tokens are of sound quality.

The *Fed Chair* expands liquidity into the AMM when Dola is above 1$ in price, reducing Dola price by selling half for the paired tokens.
The *Fed Chair* pulls liquidity when the price is below 1$, by selling the paired tokens for Dola before burning the dola, pushing up the price in the process.

Inverse Finance currently operating the *YearnFed* in partnership with Yearn Finance, with a *ConvexFed*, *AuraFed* and *VelodromeFed* nearing completion.
