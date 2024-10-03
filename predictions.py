import MetaTrader5 as mt5
import pandas as pd
import logging
import numpy as np
from sklearn.preprocessing import MinMaxScaler
from sklearn.metrics import mean_absolute_error, mean_squared_error
from tensorflow.keras.models import load_model


class ForexTrader:
    def __init__(
        self, pair, timeframe, start_date, end_date, lot_size, sl_pips, tp_ratio
    ):
        self.pair = pair
        self.timeframe = timeframe
        self.start_date = start_date
        self.end_date = end_date
        self.lot_size = lot_size
        self.sl_pips = sl_pips
        self.tp_ratio = tp_ratio
        self.active_trade = False

        # Initialize logging
        logging.basicConfig(filename="trading.log", level=logging.INFO)

        # Initialize MT5
        self.initialize_mt5()

        # Load data
        self.data = self.get_data()

        # Identify zones and labels
        self.demand_zones, self.supply_zones = self.identify_zones()
        self.labels = self.label_zones()

        # Prepare training and test data
        self.X_test, self.y_test = self.prepare_data()

        # Load the model
        self.model = load_model("cnn_forex_model.h5")
        
    # Evaluate the model performance
    def evaluate_model(self):
        try:
            predicted_zones = self.model.predict(self.X_test)
            predicted_classes = np.argmax(predicted_zones, axis=1)

            # Calculate evaluation metrics
            mae = mean_absolute_error(self.y_test, predicted_classes)
            mse = mean_squared_error(self.y_test, predicted_classes)

            logging.info(f"Model Evaluation: MAE: {mae}, MSE: {mse}")
            print(f"Model Evaluation: MAE: {mae}, MSE: {mse}")

            return mae, mse
        except Exception as e:
            logging.error("Error during model evaluation: %s", e)
            return None, None

    # Initialize MT5 and login
    def initialize_mt5(self):
        try:
            if not mt5.initialize():
                logging.error("initialize() failed, error code = %s", mt5.last_error())
                quit()
            account = 5564695  # replace with your account number
            password = "D@sedase1"  # replace with your MT5 password
            server = "Deriv-Demo"
            if not mt5.login(account, password, server=server):
                logging.error(
                    "Failed to login to MT5, error code = %s", mt5.last_error()
                )
                quit()
        except Exception as e:
            logging.error("Error initializing MetaTrader: %s", e)

    # Function to get historical data
    def get_data(self):
        try:
            utc_from = pd.to_datetime(self.start_date).to_pydatetime()
            utc_to = pd.to_datetime(self.end_date).to_pydatetime()
            rates = mt5.copy_rates_range(self.pair, self.timeframe, utc_from, utc_to)
            if rates is None:
                logging.error("No data retrieved, error code = %s", mt5.last_error())
                quit()
            data = pd.DataFrame(rates)
            data["time"] = pd.to_datetime(data["time"], unit="s")
            data.set_index("time", inplace=True)
            return data[["open", "high", "low", "close"]]
        except Exception as e:
            logging.error("Error fetching data: %s", e)
            quit()

    # Identify supply and demand zones using price action
    def identify_zones(self, lookback=100):
        try:
            demand_zones = []
            supply_zones = []
            for i in range(lookback, len(self.data)):
                # Find local lows (demand zones) and highs (supply zones)
                if (
                    self.data["low"][i]
                    == self.data["low"][i - lookback : i + lookback].min()
                ):
                    demand_zones.append(self.data["low"][i])
                if (
                    self.data["high"][i]
                    == self.data["high"][i - lookback : i + lookback].max()
                ):
                    supply_zones.append(self.data["high"][i])
            return demand_zones, supply_zones
        except Exception as e:
            logging.error("Error identifying zones: %s", e)
            return [], []

    # Label data as supply, demand, or neutral zones
    def label_zones(self):
        try:
            labels = []
            for i in range(len(self.data)):
                close_price = self.data.iloc[i][
                    "close"
                ]  # Use close price to label zones
                if any(abs(close_price - zone) < 0.005 for zone in self.demand_zones):
                    labels.append(0)  # Demand zone (buy)
                elif any(abs(close_price - zone) < 0.005 for zone in self.supply_zones):
                    labels.append(1)  # Supply zone (sell)
                else:
                    labels.append(2)  # Neutral zone (hold)
            return np.array(labels)
        except Exception as e:
            logging.error("Error labeling zones: %s", e)
            return np.array([])

    # Prepare training and test data
    def prepare_data(self, seq_length=60):
        try:
            scaler = MinMaxScaler()
            scaled_data = scaler.fit_transform(
                self.data[["open", "high", "low", "close"]]
            )
            train_size = int(len(scaled_data) * 0.8)
            test_data = scaled_data[train_size:]

            return self.create_sequences_and_labels(
                test_data, seq_length, self.labels[train_size:]
            )
        except Exception as e:
            logging.error("Error preparing data: %s", e)
            return np.array([]), np.array([])

    # Create sequences and labels
    def create_sequences_and_labels(self, data, seq_length, labels):
        try:
            sequences = []
            sequence_labels = []
            for i in range(seq_length, len(data)):
                sequences.append(data[i - seq_length : i])
                sequence_labels.append(labels[i])
            return np.array(sequences), np.array(sequence_labels)
        except Exception as e:
            logging.error("Error creating sequences and labels: %s", e)
            return np.array([]), np.array([])

    # Place trade based on action
    def place_trade(self, action):
        try:
            # If there's already an active trade, do not place another one
            if self.active_trade:
                logging.info("Trade already active, waiting for it to close.")
                return

            # Get live market price
            tick = mt5.symbol_info_tick(self.pair)
            if not tick:
                logging.error("Failed to get market data.")
                return

            price = tick.ask if action == "buy" else tick.bid  # Buy at ask, sell at bid

            # Get symbol information
            symbol_info = mt5.symbol_info(self.pair)
            if symbol_info is None:
                logging.error("Symbol %s not found.", self.pair)
                return

            # Ensure the symbol is visible
            if not symbol_info.visible:
                logging.info("%s is not visible, trying to switch it on.", self.pair)
                if not mt5.symbol_select(self.pair, True):
                    logging.error("Failed to select symbol: %s", self.pair)
                    return

            # Define lot size and pip value
            pip_value = symbol_info.point

            # Calculate stop-loss and take-profit prices
            sl_price = (
                price - self.sl_pips * pip_value
                if action == "buy"
                else price + self.sl_pips * pip_value
            )
            tp_price = (
                price + self.sl_pips * self.tp_ratio * pip_value
                if action == "buy"
                else price - self.sl_pips * self.tp_ratio * pip_value
            )

            # Prepare the order request
            request = {
                "action": mt5.TRADE_ACTION_DEAL,
                "symbol": self.pair,
                "volume": self.lot_size,
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
                logging.error("Failed to place order: %s", result.retcode)
            else:
                logging.info("Trade placed successfully: %s at %s", action, price)
                self.active_trade = (
                    True  # Set active_trade to True when a trade is placed
                )
        except Exception as e:
            logging.error("Error placing trade: %s", e)

    # Check if there's an active trade and reset flag if trade has closed
    def check_trade_status(self):
        try:
            # Get open positions for the symbol
            positions = mt5.positions_get(symbol=self.pair)

            # If no active positions are open, reset the active_trade flag
            if len(positions) == 0:
                self.active_trade = False
                logging.info("No active trades, ready to place a new trade.")
        except Exception as e:
            logging.error("Error checking trade status: %s", e)

    # Place trades based on predicted zones (0: demand zone, 1: supply zone, 2: neutral)
    def place_trade_based_on_zone(self, prediction):
        self.check_trade_status()  # Check if there's an active trade before placing a new one

        # Only place a trade if no active trade exists
        if not self.active_trade:
            if prediction == 0:  # Demand zone - Buy trade
                self.place_trade("buy")
            elif prediction == 1:  # Supply zone - Sell trade
                self.place_trade("sell")
            else:
                logging.info("No trade in neutral zone.")
        else:
            logging.info(
                "Waiting for the current trade to close before placing a new one."
            )

    # Execute trades based on predictions
    def execute_trades(self):
        try:
            predicted_zones = self.model.predict(self.X_test)
            predicted_zones = np.argmax(predicted_zones, axis=1)

            for prediction in predicted_zones:
                self.place_trade_based_on_zone(prediction)
        except Exception as e:
            logging.error("Error executing trades: %s", e)

    # Shutdown MT5 after trading is done
    def shutdown(self):
        try:
            mt5.shutdown()
            logging.info("MT5 shutdown successfully.")
        except Exception as e:
            logging.error("Error shutting down MT5: %s", e)


# Usage Example
if __name__ == "__main__":
    trader = ForexTrader(
        pair="EURUSD",
        timeframe=mt5.TIMEFRAME_M15,
        start_date="2020-01-01",
        end_date="2024-09-30",
        lot_size=0.01,
        sl_pips=200,
        tp_ratio=2,
    )
    # Evaluate the trained model
    trader.evaluate_model()

    # Execute trades
    trader.execute_trades()

    # Shutdown after trading is done
    trader.shutdown()
