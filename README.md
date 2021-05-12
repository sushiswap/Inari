# Inari

[Inari](https://etherscan.io/address/0x8a8038243f1c5f3cf8b8d59000d31b467fd4bef6#code) is a simple ‘zap’ in/out router for token staking, swap and migration.

Example calls, which can also be combined using `batch()`:

**Stake Sushi to:**

* **Aave** **(xSushi)**: `stakeSushiToAave()`
* **Bento** **(xSushi or crXsushi)**: `stakeSushiToBento()`, `stakeSushiToCreamToBento()`
* **Cream** **(Sushi or xSushi)**: `sushiToCream()`, `stakeSushiToCream()`

**Turn tokens or ETH into SLP:**

* `zapIn()`, `zapOut()` 
* **Bento (SLP)**: `zapToBento()`
