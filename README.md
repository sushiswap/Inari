# Inari

[Inari](https://etherscan.io/address/0x195E8262AA81Ba560478EC6Ca4dA73745547073f#code) is a simple ‘zap’ in/out router for token staking, swap and migration.

Example calls, which can also be combined using `batch()`:

**Stake Sushi to:**

* **Aave** **(xSushi)**: `stakeSushiToAave()`
* **Bento** **(xSushi or crXsushi)**: `stakeSushiToBento()`, `stakeSushiToCreamToBento()`
* **Cream** **(Sushi or xSushi)**: `sushiToCream()`, `stakeSushiToCream()`

**Turn tokens or ETH into SLP:**

* `zapIn()`, `zapOut()` 
* **Bento (SLP)**: `zapToBento()`
