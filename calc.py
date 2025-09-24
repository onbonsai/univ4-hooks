from math import sqrt, floor

# set the starting amounts for usdc and zstrat to calculate the starting price for the pool

usdcAmount = 1e6  # 10 USDC (6 decimals)
zstratAmount = 1000 * 1e18  # 1 billion ZSTRAT (18 decimals)

USDC_BASE = "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"
ZSTRAT_BASE = "0x2Add1065570c3847716aA9C52DF81A5E56172055"


# Sort addresses to determine token0 and token1 (token0 = lower address)
if int(ZSTRAT_BASE, 16) < int(USDC_BASE, 16):
    token0 = zstratAmount
    token1 = usdcAmount
    token0_addr = ZSTRAT_BASE
    token1_addr = USDC_BASE
else:
    token0 = usdcAmount
    token1 = zstratAmount
    token0_addr = USDC_BASE
    token1_addr = ZSTRAT_BASE

result = floor(sqrt(token1 / token0) * 2**96)

print(result)