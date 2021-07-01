# Inari

[Inari](https://etherscan.io/address/0xbD3d5153fe074EF07ECC3696785BA66849bEb84B#code) is a simple ‘zap’ in/out router for token staking, swap and migration.

Example calls, which can also be combined using `batch()`:

**Stake Sushi to:**

* **Aave** **(xSushi)**: `stakeSushiToAave()`
* **Bento** **(xSushi or crXsushi)**: `stakeSushiToBento()`, `stakeSushiToCreamToBento()`
* **Cream** **(Sushi or xSushi)**: `sushiToCream()`, `stakeSushiToCream()`

**Turn tokens or ETH into SLP:**

* `zapIn()`, `zapOut()` 
* **Bento (SLP)**: `zapToBento()`
