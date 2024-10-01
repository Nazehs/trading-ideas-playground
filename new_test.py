import yfinance as yf
import pandas as pd
import numpy as np
from sklearn.preprocessing import MinMaxScaler
from sklearn.metrics import mean_absolute_error, mean_squared_error
import tensorflow as tf
from tensorflow.keras.models import Sequential
from tensorflow.keras.layers import Dense, Conv1D, MaxPooling1D, LSTM, Flatten, Dropout, Attention
from keras_tuner.tuners import BayesianOptimization
import backtrader as bt
import math

# Parameters
pair = 'EURUSD_M15.csv'  # Forex pair
start_date = '2023-12-01'
end_date = '2024-08-30'
initial_balance = 10000  # Starting balance in USD
risk_per_trade = 0.01  # Risk 1% per trade
sl_pips = 25  # Stop-loss in pips
tp_ratio = 2  # Take profit is 2x stop-loss
pip_value = 0.0001  # Pip value for EUR/USD

# Function to get historical data from the CSV file and clean it up
def get_data(pair):
    data = pd.read_csv(pair, sep='\t', header=None)
    data.columns = ['Date', 'Time', 'Open', 'High', 'Low', 'Close', 'TickVol', 'Vol', 'Spread']
    data = data.drop(index=0)
    # Combine Date and Time into a single datetime column
    data['Datetime'] = pd.to_datetime(data['Date'] + ' ' + data['Time'])
    data.set_index('Datetime', inplace=True)
    
    # Remove the Date and Time columns
    data.drop(['Date', 'Time'], axis=1, inplace=True)
    
    # Ensure all columns are numeric
    data = data.apply(pd.to_numeric, errors='coerce')
    
    # Drop rows with missing (NaN) values
    data = data.dropna()
    
    return data[['Open', 'High', 'Low', 'Close', 'TickVol']]  # Return only relevant columns

# Load the data
data = get_data(pair)

# Preprocessing the data (normalization using MinMaxScaler)
scaler = MinMaxScaler()
scaled_data = scaler.fit_transform(data[['Open', 'High', 'Low', 'Close', 'TickVol']])

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

# Evaluation metrics: MAE, RMSE
def calculate_metrics(y_true, y_pred):
    mae = mean_absolute_error(y_true, y_pred)
    rmse = math.sqrt(mean_squared_error(y_true, y_pred))
    return mae, rmse

# Build the model with Attention mechanism
def build_cnn_lstm_model(hp):
    model = Sequential()

    # CNN layers for pattern recognition
    model.add(Conv1D(filters=hp.Int('filters', 32, 128, step=32),
                     kernel_size=hp.Choice('kernel_size', [3, 5]),
                     activation='relu', input_shape=(X.shape[1], X.shape[2])))
    model.add(MaxPooling1D(pool_size=hp.Choice('pool_size', [2, 3])))

    # LSTM for temporal dependencies
    lstm_output = LSTM(units=hp.Int('lstm_units', 32, 128, step=32), return_sequences=True)(model.output)
    
    # Attention mechanism: Pass LSTM output as both query and value
    attention_output = tf.keras.layers.Attention()([lstm_output, lstm_output])
    
    # Flatten the output for Dense layers
    flatten_output = Flatten()(attention_output)

    # Additional Dense layers for learning
    model.add(Dense(hp.Int('dense_units', 32, 128, step=32), activation='relu'))
    model.add(Dropout(hp.Float('dropout', 0.2, 0.5, step=0.1)))
    
    # Output layer (predicting the next closing price)
    model.add(Dense(1))
    
    model.compile(optimizer=tf.keras.optimizers.Adam(hp.Float('learning_rate', 1e-4, 1e-2, sampling='log')),
                  loss='mean_squared_error')

    return model

# Bayesian Optimization tuner
tuner = BayesianOptimization(
    build_cnn_lstm_model,
    objective='val_loss',
    max_trials=10,
    executions_per_trial=2,
    directory='my_dir',
    project_name='cnn_lstm_optimization'
)

# Perform tuning
tuner.search(X, y, epochs=5, validation_split=0.2)

# Get the best hyperparameters
best_hps = tuner.get_best_hyperparameters(num_trials=1)[0]
model = tuner.hypermodel.build(best_hps)

# Train the optimized model
history = model.fit(X, y, epochs=20, validation_split=0.2, batch_size=32)

# Predict the next prices
predicted_prices = model.predict(X)

# Reshape predicted_prices to 2D if it is 3D
predicted_prices = predicted_prices.reshape(-1, 1)

# Convert predictions back to actual price values using inverse_transform
predicted_prices_rescaled = scaler.inverse_transform(
    np.concatenate([np.zeros((len(predicted_prices), 4)), predicted_prices], axis=1)
)[:, -1]

# Convert actual closing prices back to their original values
actual_prices = scaler.inverse_transform(scaled_data[seq_length:])[:, 3]  # Actual closing prices

# Calculate MAE and RMSE
mae, rmse = calculate_metrics(actual_prices, predicted_prices_rescaled)
print(f'MAE: {mae}, RMSE: {rmse}')

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

# Backtrader Strategy Class
class CNNLSTMStrategy(bt.Strategy):
    params = (
        ('risk_per_trade', risk_per_trade),
        ('sl_pips', sl_pips),
        ('tp_ratio', tp_ratio),
        ('pip_value', pip_value),
    )

    def __init__(self):
        self.zones = zones
        self.data_close = self.datas[0].close
        self.balance = initial_balance
        self.current_zone = None
        self.zone_index = 0
        self.wins = 0
        self.losses = 0
        self.total_profit = 0
        self.max_drawdown = 0
        self.highest_balance = initial_balance

    def next(self):
        if self.zone_index < len(self.zones):
            zone_type, idx = self.zones[self.zone_index]

            # Check if we are at the zone's index
            if len(self) == idx:
                entry_price = self.data_close[0]

                # Set SL and TP
                sl_price = entry_price - self.params.sl_pips * self.params.pip_value if zone_type == 'Demand' else entry_price + self.params.sl_pips * self.params.pip_value
                tp_price = entry_price + (self.params.sl_pips * self.params.tp_ratio) * self.params.pip_value if zone_type == 'Demand' else entry_price - (self.params.sl_pips * self.params.tp_ratio) * self.params.pip_value

                # Risk per trade
                risk_amount = self.balance * self.params.risk_per_trade

                # Place the buy/sell order
                if zone_type == 'Demand':
                    self.buy_bracket(price=entry_price, stopprice=sl_price, limitprice=tp_price)
                elif zone_type == 'Supply':
                    self.sell_bracket(price=entry_price, stopprice=sl_price, limitprice=tp_price)

                self.zone_index += 1

    def notify_trade(self, trade):
        if trade.isclosed:
            pnl = trade.pnlcomm
            self.total_profit += pnl

            if pnl > 0:
                self.wins += 1
            else:
                self.losses += 1

            self.balance += pnl
            self.highest_balance = max(self.highest_balance, self.balance)
            drawdown = self.highest_balance - self.balance
            self.max_drawdown = max(self.max_drawdown, drawdown)

# Add Data Feed to Cerebro
class CustomPandasData(bt.feeds.PandasData):
    lines = ('TickVol',)
    params = (('datetime', None), ('open', 'Open'), ('high', 'High'), ('low', 'Low'), ('close', 'Close'), ('volume', 'TickVol'), ('openinterest', None))

datafeed = CustomPandasData(dataname=data)  # Use the custom data feed
cerebro = bt.Cerebro()
cerebro.adddata(datafeed)

# Add strategy
cerebro.addstrategy(CNNLSTMStrategy)

# Set starting cash
cerebro.broker.set_cash(initial_balance)

# Run backtest
print(f'Starting Portfolio Value: {initial_balance}')
cerebro.run()
print(f'Final Portfolio Value: {cerebro.broker.getvalue()}')
