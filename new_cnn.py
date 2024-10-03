import MetaTrader5 as mt5
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
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
timeframe = mt5.TIMEFRAME_M15
start_date = '2020-01-01'
end_date = '2024-09-30'
sl_pips = 200
tp_ratio = 2
lookback = 100
min_movement = 0.001

# Initialize MT5 and login
def initialize_mt5():
    if not mt5.initialize():
        print("initialize() failed, error code =", mt5.last_error())
        quit()
    account = 5564695  # Replace with your account number
    password = "D@sedase1"  # Replace with your MT5 password
    server = "Deriv-Demo"  # Change to your live server for real trading
    if not mt5.login(account, password, server=server):
        print("Failed to login to MT5, error code =", mt5.last_error())
        quit()

initialize_mt5()

# Function to get historical data
def get_data(pair, timeframe, start_date, end_date):
    utc_from = pd.to_datetime(start_date).to_pydatetime()
    utc_to = pd.to_datetime(end_date).to_pydatetime()
    rates = mt5.copy_rates_range(pair, timeframe, utc_from, utc_to)
    if rates is None:
        print("No data retrieved, error code =", mt5.last_error())
        quit()
    data = pd.DataFrame(rates)
    data['time'] = pd.to_datetime(data['time'], unit='s')
    data.set_index('time', inplace=True)
    return data[['open', 'high', 'low', 'close']]

# Load data
data = get_data(pair, timeframe, start_date, end_date)

# Identify supply and demand zones using price action
def identify_zones(data, lookback=100, min_movement=0.001):
    demand_zones = []
    supply_zones = []
    for i in range(lookback, len(data)):
        if data['low'][i] == data['low'][i-lookback:i+lookback].min() and (data['low'][i] - data['low'][i-1]) > min_movement:
            demand_zones.append(data['low'][i])
        if data['high'][i] == data['high'][i-lookback:i+lookback].max() and (data['high'][i] - data['high'][i-1]) > min_movement:
            supply_zones.append(data['high'][i])
    return demand_zones, supply_zones

# Preprocessing
scaler = MinMaxScaler()
scaled_data = scaler.fit_transform(data[['open', 'high', 'low', 'close']])
train_size = int(len(scaled_data) * 0.8)
train_data = scaled_data[:train_size]
test_data = scaled_data[train_size:]

# Label data as supply, demand, or neutral zones
def label_zones(data, demand_zones, supply_zones):
    labels = []
    for i in range(len(data)):
        close_price = data.iloc[i]['close']  # Use close price to label zones
        if any(abs(close_price - zone) < 0.005 for zone in demand_zones):  # Tolerance for proximity
            labels.append(0)  # Demand zone (buy)
        elif any(abs(close_price - zone) < 0.005 for zone in supply_zones):
            labels.append(1)  # Supply zone (sell)
        else:
            labels.append(2)  # Neutral zone (hold)
    return np.array(labels)

# Create sequences and labels
def create_sequences_and_labels(data, seq_length, labels):
    sequences = []
    sequence_labels = []
    for i in range(seq_length, len(data)):
        sequences.append(data[i-seq_length:i])
        sequence_labels.append(labels[i])
    return np.array(sequences), np.array(sequence_labels)

# Identify zones
demand_zones, supply_zones = identify_zones(data)

# Label the entire dataset based on zones
labels = label_zones(data, demand_zones, supply_zones)

# Prepare training and test data
seq_length = 60
X_train, y_train = create_sequences_and_labels(train_data, seq_length, labels[:train_size])
X_test, y_test = create_sequences_and_labels(test_data, seq_length, labels[train_size:])

# Build the CNN model
def build_cnn_model(hp):
    model = Sequential()
    model.add(Conv1D(filters=hp.Int('filters', 32, 128, step=32),
                     kernel_size=hp.Choice('kernel_size', [3, 5]),
                     activation='relu', input_shape=(X_train.shape[1], X_train.shape[2])))
    model.add(MaxPooling1D(pool_size=hp.Choice('pool_size', [2, 3])))
    model.add(Flatten())
    model.add(Dense(hp.Int('dense_units', 32, 128, step=32), activation='relu'))
    model.add(Dropout(hp.Float('dropout', 0.2, 0.5, step=0.1)))
    model.add(Dense(3, activation='softmax'))  # 3 classes: demand, supply, neutral
    model.compile(optimizer=tf.keras.optimizers.Adam(hp.Float('learning_rate', 1e-4, 1e-2, sampling='log')),
                  loss='sparse_categorical_crossentropy', metrics=['accuracy'])
    return model

# Bayesian Optimization tuner
tuner = BayesianOptimization(
    build_cnn_model,
    objective='val_loss',
    max_trials=10,
    executions_per_trial=2,
    directory='cnn_tuner_dir',
    project_name='cnn_zone_prediction'
)

# Perform tuning
tuner.search(X_train, y_train, epochs=5, validation_split=0.2)

# Train the best model
best_hps = tuner.get_best_hyperparameters(num_trials=1)[0]
model = tuner.hypermodel.build(best_hps)
history = model.fit(X_train, y_train, epochs=20, validation_split=0.2, batch_size=32)

# Predict zones on the test set
predicted_zones = model.predict(X_test)
predicted_zones = np.argmax(predicted_zones, axis=1)

# Visualization function for zones
def plot_zones(data, demand_zones, supply_zones):
    plt.figure(figsize=(12, 6))
    plt.plot(data.index, data['close'], label='Price', color='black')

    # Highlight demand zones
    for zone in demand_zones:
        plt.axhspan(zone - 0.0005, zone + 0.0005, color='green', alpha=0.3, label='Demand Zone')

    # Highlight supply zones
    for zone in supply_zones:
        plt.axhspan(zone - 0.0005, zone + 0.0005, color='red', alpha=0.3, label='Supply Zone')

    plt.title('Supply and Demand Zones')
    plt.xlabel('Time')
    plt.ylabel('Price')
    plt.legend()
    plt.show()

# Call the plot function
plot_zones(data, demand_zones, supply_zones)

# Track whether an active trade exists
active_trade = False

def place_trade(action, sl_pips, tp_ratio):
    global active_trade

    # If there's already an active trade, do not place another one
    if active_trade:
        print("Trade already active, waiting for it to close.")
        return

    # Get live market price
    tick = mt5.symbol_info_tick(pair)
    if not tick:
        print("Failed to get market data.")
        return

    price = tick.ask if action == "buy" else tick.bid  # Buy at ask, sell at bid

    # Get symbol information
    symbol_info = mt5.symbol_info(pair)
    if symbol_info is None:
        print(f"Symbol {pair} not found.")
        return
    
    # Ensure the symbol is visible
    if not symbol_info.visible:
        print(f"{pair} is not visible, trying to switch it on.")
        if not mt5.symbol_select(pair, True):
            print("Failed to select symbol:", pair)
            return

    # Define lot size and pip value
    lot = 0.01
    pip_value = symbol_info.point

    # Calculate stop-loss and take-profit prices
    sl_price = price - sl_pips * pip_value if action == "buy" else price + sl_pips * pip_value
    tp_price = price + sl_pips * tp_ratio * pip_value if action == "buy" else price - sl_pips * tp_ratio * pip_value

    # Prepare the order request
    order_type = mt5.ORDER_BUY if action == "buy" else mt5.ORDER_SELL
    request = {
        "action": mt5.TRADE_ACTION_DEAL,
        "symbol": pair,
        "volume": lot,
        "type": order_type,
        "price": price,
        "sl": sl_price,
        "tp": tp_price,
        "deviation": 10,
        "magic": 234000,
        "comment": "Trade from Python script",
        "type_time": mt5.ORDER_TIME_GTC,
        "type_filling": mt5.ORDER_FILLING_IOC
    }

    # Send the order
    result = mt5.order_send(request)

    if result.retcode != mt5.TRADE_RETCODE_DONE:
        print("Order failed, error code:", result.retcode)
    else:
        print(f"Trade placed: {action} at {price}, SL at {sl_price}, TP at {tp_price}")
        active_trade = True  # Set active trade to True

# Function to check for trade opportunities
def check_for_trade_opportunities():
    global active_trade

    # Get the latest price data
    tick = mt5.symbol_info_tick(pair)
    if not tick:
        print("Failed to get market data.")
        return

    latest_price = tick.last

    # Check for demand zone opportunity
    if not active_trade and any(abs(latest_price - zone) < 0.0005 for zone in demand_zones):
        place_trade("buy", sl_pips, tp_ratio)

    # Check for supply zone opportunity
    elif not active_trade and any(abs(latest_price - zone) < 0.0005 for zone in supply_zones):
        place_trade("sell", sl_pips, tp_ratio)

# Run continuously
try:
    while True:
        check_for_trade_opportunities()
        time.sleep(60)  # Check every minute
except KeyboardInterrupt:
    print("Program terminated by user.")

# Terminate MT5 connection when done
mt5.shutdown()
