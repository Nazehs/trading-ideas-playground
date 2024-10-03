import MetaTrader5 as mt5
import pandas as pd
import numpy as np
from sklearn.preprocessing import MinMaxScaler
from sklearn.cluster import KMeans
import math
import time

# Parameters
pair = 'EURUSD'
timeframe = mt5.TIMEFRAME_M15
start_date = '2020-12-01'
end_date = '2024-09-30'
sl_pips = 200
tp_ratio = 2

# Initialize MT5 and login
def initialize_mt5():
    if not mt5.initialize():
        print("initialize() failed, error code =", mt5.last_error())
        quit()
    account = 5564695  # replace with your account number
    password = "D@sedase1"  # replace with your MT5 password
    server = "Deriv-Demo"
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

# Preprocessing
scaler = MinMaxScaler()
scaled_data = scaler.fit_transform(data[['open', 'high', 'low', 'close']])

# K-means clustering to identify supply and demand zones
def identify_zones_kmeans(data, n_clusters=2):
    kmeans = KMeans(n_clusters=n_clusters)
    data_points = data[['low', 'high']].values
    kmeans.fit(data_points)
    labels = kmeans.labels_
    demand_zone = data_points[labels == 0].min(axis=0)[0]  # Demand zone from cluster 0
    supply_zone = data_points[labels == 1].max(axis=0)[1]  # Supply zone from cluster 1
    return demand_zone, supply_zone

# Identify supply and demand zones using K-means
demand_zone, supply_zone = identify_zones_kmeans(data)


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
    request = {
        "action": mt5.TRADE_ACTION_DEAL,
        "symbol": pair,
        "volume": lot,
        "type": mt5.ORDER_TYPE_BUY if action == "buy" else mt5.ORDER_TYPE_SELL,
        "price": price,
        "sl": sl_price,
        "tp": tp_price,
        "deviation": 20,  # Allowable price deviation in points
        "magic": 234000,  # Identifier for this strategy
        "comment": f"CNN strategy {action}",
        "type_time": mt5.ORDER_TIME_GTC,  # Good-Till-Cancelled
    }

    # Send the trade order
    result = mt5.order_send(request)
    if result.retcode != mt5.TRADE_RETCODE_DONE:
        print(f"Failed to place order: {result.retcode}")
    else:
        print(f"Trade placed successfully: {action} at {price}")
        active_trade = True  # Set active_trade to True when a trade is placed

# Check if there's an active trade and reset flag if trade has closed
def check_trade_status():
    global active_trade

    # Get open positions for the symbol
    positions = mt5.positions_get(symbol=pair)

        # If no active positions are open, reset the active_trade flag
    if len(positions) == 0:
        active_trade = False
        print("No active trades, ready to place a new trade.")



# Create trading logic based on zones
def trade_based_on_kmeans(current_price, demand_zone, supply_zone, sl_pips, tp_ratio):
    check_trade_status()

    if not active_trade:
        if current_price < demand_zone:
            place_trade("buy", sl_pips, tp_ratio)
        elif current_price > supply_zone:
            place_trade("sell", sl_pips, tp_ratio)
        else:
            print("Neutral zone, no trade.")
    else:
        print("Waiting for the current trade to close before placing a new one.")

# Trading loop
for i in range(len(data)):
    current_price = data['close'][i]
    trade_based_on_kmeans(current_price, demand_zone, supply_zone, sl_pips, tp_ratio)

# Shutdown MT5
mt5.shutdown()
