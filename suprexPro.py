import yfinance as yf
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
from sklearn.preprocessing import MinMaxScaler
import tensorflow as tf
from tensorflow.keras.models import Sequential
from tensorflow.keras.layers import Dense, Conv1D, MaxPooling1D, LSTM, Flatten, Dropout

# Parameters
pair = 'EURUSD=X'  # Forex pair
start_date = '2023-12-01'
end_date = '2024-08-30'
initial_balance = 10000  # Starting balance in USD
risk_per_trade = 0.01  # Risk 1% per trade
sl_pips = 25  # Stop-loss in pips
tp_ratio = 2  # Take profit is 2x stop-loss
pip_value = 0.0001  # Pip value for EUR/USD

# Function to get historical data from yfinance
def get_data(pair, start_date, end_date):
    data = yf.download(pair, start=start_date, end=end_date, interval='1h')
    data.dropna(inplace=True)
    return data

# Load the data
data = get_data(pair, start_date, end_date)

# Preprocessing the data
scaler = MinMaxScaler()
scaled_data = scaler.fit_transform(data[['Open', 'High', 'Low', 'Close', 'Volume']])

# Prepare the data for CNN + LSTM
def create_sequences(data, seq_length):
    sequences = []
    labels = []
    for i in range(seq_length, len(data)):
        sequences.append(data[i-seq_length:i])
        labels.append(data[i, 3])  # Use closing price as label
    return np.array(sequences), np.array(labels)

seq_length = 60  # Lookback window of 60 time steps (hours in this case)
X, y = create_sequences(scaled_data, seq_length)

# Build the CNN + LSTM model
def build_cnn_lstm_model(input_shape):
    model = Sequential()
    
    # CNN layers for pattern recognition
    model.add(Conv1D(filters=64, kernel_size=3, activation='relu', input_shape=input_shape))
    model.add(MaxPooling1D(pool_size=2))
    
    # LSTM layer for temporal dependencies
    model.add(LSTM(units=64, return_sequences=False))
    
    # Fully connected layers
    model.add(Dense(32, activation='relu'))
    model.add(Dropout(0.2))
    model.add(Dense(1))  # Predicting the next closing price
    
    model.compile(optimizer='adam', loss='mean_squared_error')
    return model

# Model input shape
input_shape = (X.shape[1], X.shape[2])

# Build the model
model = build_cnn_lstm_model(input_shape)

# Train the model
model.fit(X, y, epochs=10, batch_size=32)

# Predict the next prices
predicted_prices = model.predict(X)

# Convert back to actual price values
predicted_prices_rescaled = scaler.inverse_transform(np.concatenate([np.zeros((len(predicted_prices), 4)), predicted_prices], axis=1))[:, -1]

# Supply/Demand zone identification
def identify_zones(predictions, threshold=0.005):
    zones = []
    for i in range(1, len(predictions)):
        if predictions[i] > predictions[i - 1] * (1 + threshold):  # Demand zone
            zones.append(('Demand', i))
        elif predictions[i] < predictions[i - 1] * (1 - threshold):  # Supply zone
            zones.append(('Supply', i))
    return zones

zones = identify_zones(predicted_prices_rescaled)

# Backtesting the strategy
def backtest(zones, data, initial_balance, risk_per_trade, sl_pips, tp_ratio):
    balance = initial_balance
    for zone in zones:
        zone_type, idx = zone
        entry_price = data['Close'].iloc[idx]
        
        if zone_type == 'Demand':  # Buy trade at demand zone
            sl_price = entry_price - sl_pips * pip_value
            tp_price = entry_price + (sl_pips * tp_ratio) * pip_value
            risk_amount = balance * risk_per_trade
            
            # Simulate the trade outcome
            for j in range(idx, len(data)):
                if data['Low'].iloc[j] <= sl_price:  # SL hit
                    balance -= risk_amount
                    break
                elif data['High'].iloc[j] >= tp_price:  # TP hit
                    balance += risk_amount * tp_ratio
                    break

        elif zone_type == 'Supply':  # Sell trade at supply zone
            sl_price = entry_price + sl_pips * pip_value
            tp_price = entry_price - (sl_pips * tp_ratio) * pip_value
            risk_amount = balance * risk_per_trade
            
            # Simulate the trade outcome
            for j in range(idx, len(data)):
                if data['High'].iloc[j] >= sl_price:  # SL hit
                    balance -= risk_amount
                    break
                elif data['Low'].iloc[j] <= tp_price:  # TP hit
                    balance += risk_amount * tp_ratio
                    break

    return balance

# Run backtest on the strategy
final_balance = backtest(zones, data, initial_balance, risk_per_trade, sl_pips, tp_ratio)

# Print results
print(f"Initial Balance: ${initial_balance}")
print(f"Final Balance: ${final_balance}")
