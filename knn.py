import pandas as pd
import numpy as np
import yfinance as yf
import matplotlib.pyplot as plt
from sklearn.neighbors import KNeighborsRegressor
import talib as ta

# Step 1: Download Historical Data (AAPL as an example)
df = yf.download('AAPL', start='2020-01-01', end='2023-01-01')

# Step 2: Calculate Technical Indicators
df['RSI'] = ta.RSI(df['Close'], timeperiod=14)
df['SMA_50'] = df['Close'].rolling(window=50).mean()
df['SMA_200'] = df['Close'].rolling(window=200).mean()

# Drop rows with NaN values
df.dropna(inplace=True)

# Step 3: Train KNN for Support and Resistance Levels

# Features (using OHLC data as features for KNN)
X = df[['Open', 'High', 'Low', 'Close']].values

# Target (for S&R, we use Close prices)
y = df['Close'].values

# Train KNN model (using 5 nearest neighbors)
knn = KNeighborsRegressor(n_neighbors=5)
knn.fit(X, y)

# Predict Support and Resistance levels
df['KNN_Pred'] = knn.predict(X)

# Step 4: Define Trading Logic Based on KNN and RSI
def apply_trading_logic(df):
    # Buy when price hits KNN support and RSI < 30 (oversold)
    df['Signal'] = 0
    df.loc[(df['Close'] < df['KNN_Pred']) & (df['RSI'] < 30), 'Signal'] = 1  # Buy signal
    
    # Sell when price hits KNN resistance and RSI > 70 (overbought)
    df.loc[(df['Close'] > df['KNN_Pred']) & (df['RSI'] > 70), 'Signal'] = -1  # Sell signal

    return df

df = apply_trading_logic(df)

# Step 5: Plot the Signals, Prices, KNN Predicted Levels, and RSI

plt.figure(figsize=(14, 8))

# Plot Close price and KNN-predicted S&R levels
plt.plot(df.index, df['Close'], label='Close Price')
plt.plot(df.index, df['KNN_Pred'], label='KNN Predicted S&R', linestyle='--', color='red')

# Plot Buy and Sell Signals
plt.plot(df[df['Signal'] == 1].index, df['Close'][df['Signal'] == 1], '^', markersize=10, color='g', label='Buy Signal')
plt.plot(df[df['Signal'] == -1].index, df['Close'][df['Signal'] == -1], 'v', markersize=10, color='r', label='Sell Signal')

# Title and labels
plt.legend(loc='best')
plt.title('KNN S&R with RSI and Trading Signals')
plt.xlabel('Date')
plt.ylabel('Price')
plt.show()

# Step 6: Backtest the Strategy

# Create a 'Position' column to track long (1) or short (-1)
df['Position'] = df['Signal'].shift()

# Calculate daily returns
df['Daily_Return'] = df['Close'].pct_change()

# Calculate strategy returns (only apply when in a position)
df['Strategy_Return'] = df['Daily_Return'] * df['Position']

# Cumulative returns
df['Cumulative_Strategy_Return'] = (1 + df['Strategy_Return']).cumprod()

# Step 7: Plot the Cumulative Strategy Returns
plt.figure(figsize=(14, 8))
plt.plot(df.index, df['Cumulative_Strategy_Return'], label='KNN + RSI Strategy Return', color='blue')
plt.title('Cumulative Returns of KNN + RSI Strategy')
plt.legend(loc='best')
plt.xlabel('Date')
plt.ylabel('Cumulative Return')
plt.show()

# Summary of strategy returns
print(f"Total Strategy Return: {df['Cumulative_Strategy_Return'].iloc[-1] - 1:.2%}")
