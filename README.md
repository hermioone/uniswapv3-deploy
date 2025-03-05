# 问题总结

## milestone_2

按照白皮书修改代码后，点击前端的添加流动性按钮，结果添加流动性失败，从浏览器的 console 中看到报了一个 "ERC20InsufficientAllowance" 的异常。

在 UniswapV3Pool 的 mint 函数中，只是修改了 amount0 和 amount1 的获取方式，从
```solidity
amount0 = 0.998976618347425280 ether;
amount1 = 5000 ether;
```

修改为：

```solidity
amount0 = Math.calcAmount0Delta(
    TickMath.getSqrtRatioAtTick(slot0.tick),
    TickMath.getSqrtRatioAtTick(upperTick),
    amount
);

amount1 = Math.calcAmount1Delta(
    TickMath.getSqrtRatioAtTick(slot0.tick),
    TickMath.getSqrtRatioAtTick(lowerTick),
    amount
);
```

把 amount0 和 amount1 修改成回去则添加流动性不会报错。所以问题就出在计算 amount0 和 amount1 的方式上。

仔细查看了代码，发现 amount0 和 amount1 的计算都依赖于 tick，而 `0.998976618347425280 ether` 和 `5000 ether` 这对组合都是基于 tick 为 85176，tickLower 为 84222，tickUpper 为 86129 的基础上计算出来的。

但是在 UniswapV3Pool 的部署脚本中，将 Pool 的当前 tick 设置为 0，而根据0这个当前 tick 和 84222 及 86129 计算出来的 amount0 和 amount1 不再等于 `0.998976618347425280 ether` 和 `5000 ether`（因为目前版本 amount0 和 amount1 的计算仅考虑了 tickLower < tickCurrent < tickUpper 这种情况，而实际的情况则是 tickCurrent < tickLower < tickUpper）。所以解决办法就是将部署脚本中的 Pool 的 tick 参数设置为 85176，sqrtPriceX96 设置为 5602277097478614198912276234240。

![image-20250304015040205](https://hermione-pic.oss-cn-beijing.aliyuncs.com/uPic/image-20250304015040205.png)
