import MetaTrader5 as mt5
import pandas as pd
import numpy as np
from sklearn.preprocessing import MinMaxScaler
from sklearn.metrics import mean_absolute_error, mean_squared_error
import tensorflow as tf
from tensorflow.keras.models import Sequential
from tensorflow.keras.layers import Dense, Conv1D, MaxPooling1D, Flatten, Dropout
from keras_tuner.tuners import BayesianOptimization
import math
import time

# Parameters
pair = 'EURUSD'
timeframe = mt5.TIMEFRAME_M15  # 15-minute timeframe
start_date = '2020-12-01'
end_date = '2024-09-30'
initial_balance = 10000  # Starting balance in USD
risk_per_trade = 0.01  # Risk 1% per trade
sl_pips = 200  # Stop-loss in pips
tp_ratio = 2  # Take profit is 2x stop-loss
#pip_value = 0.0001  # Pip value for EUR/USD

# Initialize MT5 and login
def initialize_mt5():
    if not mt5.initialize():
        print("initialize() failed, error code =", mt5.last_error())
        quit()

    # Login to your account
    account = 5564695  # replace with your account number
    password = "D@sedase1"  # replace with your MT5 password
    server = "Deriv-Demo"
    if not mt5.login(account, password, server=server):
        print("Failed to login to MT5, error code =", mt5.last_error())
        quit()

initialize_mt5()

# Function to get historical data from MT5
def get_data(pair, timeframe, start_date, end_date):
    utc_from = pd.to_datetime(start_date).to_pydatetime()
    utc_to = pd.to_datetime(end_date).to_pydatetime()

    # Requesting historical data from MT5
    rates = mt5.copy_rates_range(pair, timeframe, utc_from, utc_to)
    if rates is None:
        print("No data retrieved, error code =", mt5.last_error())
        quit()

    data = pd.DataFrame(rates)
    data['time'] = pd.to_datetime(data['time'], unit='s')
    data.set_index('time', inplace=True)
    return data[['open', 'high', 'low', 'close']]

# Load the data
data = get_data(pair, timeframe, start_date, end_date)

# Preprocessing the data (normalization using MinMaxScaler)
scaler = MinMaxScaler()
scaled_data = scaler.fit_transform(data[['open', 'high', 'low', 'close']])

# Create train-test split (80% training, 20% testing)
train_size = int(len(scaled_data) * 0.8)
train_data = scaled_data[:train_size]
test_data = scaled_data[train_size:]

# Prepare the data for CNN
def create_sequences(data, seq_length):
    sequences = []
    labels = []
    for i in range(seq_length, len(data)):
        sequences.append(data[i-seq_length:i])
        labels.append(data[i, 3])  # Use closing price as label
    return np.array(sequences), np.array(labels)

seq_length = 60  # Lookback window of 60 time steps
X_train, y_train = create_sequences(train_data, seq_length)
X_test, y_test = create_sequences(test_data, seq_length)

# Evaluation metrics: MAE, RMSE
def calculate_metrics(y_true, y_pred):
    mae = mean_absolute_error(y_true, y_pred)
    rmse = math.sqrt(mean_squared_error(y_true, y_pred))
    return mae, rmse

# Build the CNN model
def build_cnn_model(hp):
    model = Sequential()

    # CNN layers for pattern recognition
    model.add(Conv1D(filters=hp.Int('filters', 32, 128, step=32),
                     kernel_size=hp.Choice('kernel_size', [3, 5]),
                     activation='relu', input_shape=(X_train.shape[1], X_train.shape[2])))
    model.add(MaxPooling1D(pool_size=hp.Choice('pool_size', [2, 3])))

    # Flatten the CNN output for Dense layers
    model.add(Flatten())

    # Dense layers for learning more complex features
    model.add(Dense(hp.Int('dense_units', 32, 128, step=32), activation='relu'))
    model.add(Dropout(hp.Float('dropout', 0.2, 0.5, step=0.1)))

    # Output layer (predicting the next closing price)
    model.add(Dense(1))

    # Compile the model with a loss function and optimizer
    model.compile(optimizer=tf.keras.optimizers.Adam(hp.Float('learning_rate', 1e-4, 1e-2, sampling='log')),
                  loss='mean_squared_error')  # MSE for regression tasks
    return model

# Bayesian Optimization tuner
tuner = BayesianOptimization(
    build_cnn_model,
    objective='val_loss',
    max_trials=10,
    executions_per_trial=2,
    directory='cnn_tuner_dir',
    project_name='cnn_optimization'
)

# Perform tuning
tuner.search(X_train, y_train, epochs=5, validation_split=0.2)

# Get the best hyperparameters
best_hps = tuner.get_best_hyperparameters(num_trials=1)[0]
model = tuner.hypermodel.build(best_hps)

# Train the optimized model
history = model.fit(X_train, y_train, epochs=20, validation_split=0.2, batch_size=32)

# Predict the next prices on the test set
predicted_prices = model.predict(X_test)

# Rescale the predicted prices back to actual price values
predicted_prices = predicted_prices.reshape(-1, 1)
predicted_prices_rescaled = scaler.inverse_transform(
    np.concatenate([np.zeros((len(predicted_prices), 3)), predicted_prices], axis=1)
)[:, -1]

# Convert actual closing prices back to their original values (for test set)
actual_prices = scaler.inverse_transform(test_data[seq_length:])[:, 3]  # Actual closing prices

# Trim predicted prices to match the actual prices length
predicted_prices_rescaled = predicted_prices_rescaled[:len(actual_prices)]

# Calculate MAE and RMSE
mae, rmse = calculate_metrics(actual_prices, predicted_prices_rescaled)
print(f'MAE: {mae}, RMSE: {rmse}')

# Function to place a buy or sell order
def place_trade(action, sl_pips, tp_ratio):
    tick = mt5.symbol_info_tick(pair)
    if not tick:
        print("Failed to get market data.")
        return
    
    price = tick.ask if action == "buy" else tick.bid  # Get live market price

    symbol_info = mt5.symbol_info(pair)
    if symbol_info is None:
        print(f"Symbol {pair} not found.")
        return
    
    if not symbol_info.visible:
        print(pair,  "is not visible, tryint to switch on")
        if not mt5.symbol_select(pair, True):
            print("symbol select failed", pair)
            mt5.shutdown()
            quit()


    lot = 0.01  # Define lot size
    pip_value = mt5.symbol_info(pair).point


    sl_price = price - sl_pips * pip_value if action == "buy" else price + sl_pips * pip_value
    tp_price = price + sl_pips * tp_ratio * pip_value if action == "buy" else price - sl_pips * tp_ratio * pip_value

    request = {
        "action": mt5.TRADE_ACTION_DEAL,
        "symbol": pair,
        "volume": lot,
        "type": mt5.ORDER_TYPE_BUY if action == "buy" else mt5.ORDER_TYPE_SELL,
        "price": price,
        "sl": sl_price,
        "tp": tp_price,
        #"deviation": 20,
        "magic": 234000,
        "comment": f"CNN strategy {action}",
       # "type_time": mt5.ORDER_TIME_GTC,
       # "type_filling": mt5.ORDER_FILLING_IOC,
    }

    result = mt5.order_send(request)
    if result.retcode != mt5.TRADE_RETCODE_DONE:
        print(f"Failed to place order: {result.retcode}")
    else:
        print(f"Trade placed successfully: {action} at {price}")

# Example of placing a trade based on predictions
for i in range(1, len(predicted_prices_rescaled)):
    if predicted_prices_rescaled[i] > predicted_prices_rescaled[i - 1]:
        place_trade("buy", sl_pips, tp_ratio)
    elif predicted_prices_rescaled[i] < predicted_prices_rescaled[i - 1]:
        place_trade("sell", sl_pips, tp_ratio)

# Shutdown MT5 after finishing
mt5.shutdown()
