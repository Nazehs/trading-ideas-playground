import MetaTrader5 as mt5
import pandas as pd
import numpy as np
from sklearn.preprocessing import MinMaxScaler
import tensorflow as tf
from tensorflow.keras.models import Sequential
from tensorflow.keras.layers import Dense, Conv1D, MaxPooling1D, Flatten, Dropout
from keras_tuner.tuners import BayesianOptimization
import logging


# Parameters
pair = 'EURUSD'
timeframe = mt5.TIMEFRAME_M15
start_date = '2020-01-01'
end_date = '2024-09-30'
sl_pips = 200
tp_ratio = 2

# Initialize MT5 and login
def initialize_mt5():
    try:
        if not mt5.initialize():
            print("initialize() failed, error code =", mt5.last_error())
            quit()
        account = 5564695  # replace with your account number
        password = "D@sedase1"  # replace with your MT5 password
        server = "Deriv-Demo"
        if not mt5.login(account, password, server=server):
            print("Failed to login to MT5, error code =", mt5.last_error())
            quit()
    except Exception as e:
        logging.error(f"Error initializing metatrader: {e}")
        
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
def identify_zones(data, lookback=100):
    demand_zones = []
    supply_zones = []
    for i in range(lookback, len(data)):
        # Find local lows (demand zones) and highs (supply zones)
        if data['low'][i] == data['low'][i-lookback:i+lookback].min():
            demand_zones.append(data['low'][i])
        if data['high'][i] == data['high'][i-lookback:i+lookback].max():
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

# Save the model in HDF5 format
model.save("cnn_forex_model.h5")
