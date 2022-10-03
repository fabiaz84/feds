**Convex Fed**

The convex fed functions by providing Dola liquidity into Curve Finance stablecoin pools, and then staking the Liquidity Provider tokens for said pools  in the Convex system.

**Roles**

There are two main privileged roles in the Convex Fed: *gov* and *chair*.
The *gov* role can set the *chair* role, and also sets constraints on the *chair* in the form of max allowable loss, when conducting different Fed operations.
The *chair* role can expand and contract supply of Dola, while also being able to take profit from Curve LP tokens.