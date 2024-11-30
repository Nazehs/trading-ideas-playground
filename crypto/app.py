import ccxt
import pandas as pd
import numpy as np
from pandas_ta import highest, lowest
import matplotlib.pyplot as plt
import logging


class TradingBot:
    def __init__(
        self,
        exchange_name,
        api_key,
        api_secret,
        symbol,
        timeframe="15m",
        limit=500,
        initial_balance=10000,
        position_size=1.0,
    ):
        """Initialize the bot with exchange and trading parameters."""
        self.exchange = getattr(ccxt, exchange_name)(
            {"apiKey": api_key, "secret": api_secret}
        )
        self.symbol = symbol
        self.timeframe = timeframe
        self.limit = limit
        self.initial_balance = initial_balance
        self.balance = self.initial_balance
        self.position_size = position_size  # Fraction of balance to use per trade
        self.data = None
        self.yesterday_high = None
        self.yesterday_low = None
        self.trades = []  # Store trade results
        self.equity_curve = []
        # Set up logging
        logging.basicConfig(
            level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
        )

    def fetch_data(self):
        """Fetch historical OHLCV data."""
        try:
            bars = self.exchange.fetch_ohlcv(
                self.symbol, self.timeframe, limit=self.limit
            )
            df = pd.DataFrame(
                bars, columns=["timestamp", "open", "high", "low", "close", "volume"]
            )
            df["timestamp"] = pd.to_datetime(df["timestamp"], unit="ms")
            self.data = df
        except Exception as e:
            logging.error(f"Error fetching data: {e}")
            raise

    def calculate_yesterday_high_low(self):
        """Calculate yesterday's high and low levels."""
        self.data["date"] = self.data["timestamp"].dt.date
        daily_data = (
            self.data.groupby("date")
            .agg({"high": "max", "low": "min", "close": "last"})
            .shift(1)
        )
        self.yesterday_high = daily_data["high"].iloc[-1]
        self.yesterday_low = daily_data["low"].iloc[-1]

    def identify_order_blocks(self):
        """Identify potential order blocks."""
        self.data["highest"] = highest(self.data["high"], length=3)
        self.data["lowest"] = lowest(self.data["low"], length=3)

        self.data["order_block_high"] = np.where(
            self.data["high"] > self.data["highest"].shift(1), self.data["high"], np.nan
        )
        self.data["order_block_low"] = np.where(
            self.data["low"] < self.data["lowest"].shift(1), self.data["low"], np.nan
        )

    def calculate_fibonacci_levels(self):
        """Calculate Fibonacci retracement levels."""
        levels = {
            "0.236": self.yesterday_low
            + (self.yesterday_high - self.yesterday_low) * 0.236,
            "0.382": self.yesterday_low
            + (self.yesterday_high - self.yesterday_low) * 0.382,
            "0.5": self.yesterday_low
            + (self.yesterday_high - self.yesterday_low) * 0.5,
            "0.618": self.yesterday_low
            + (self.yesterday_high - self.yesterday_low) * 0.618,
            "0.786": self.yesterday_low
            + (self.yesterday_high - self.yesterday_low) * 0.786,
        }
        return levels

    def backtest(self):
        """Run the backtest on historical data."""
        logging.info(f"Backtesting strategy for {self.symbol}...")
        self.fetch_data()
        self.calculate_yesterday_high_low()
        self.identify_order_blocks()
        fib_levels = self.calculate_fibonacci_levels()

        buy_zone = fib_levels["0.618"]
        sell_zone = fib_levels["0.236"]

        position = None  # Dict to hold position info
        self.equity_curve = [
            {"timestamp": self.data["timestamp"].iloc[0], "balance": self.balance}
        ]

        for i in range(len(self.data)):
            row = self.data.iloc[i]

            # Buy signal
            if row["low"] <= buy_zone and row["close"] > buy_zone and position is None:
                # Calculate position size in units
                units = (self.balance * self.position_size) / row["close"]
                entry_price = row["close"]
                entry_timestamp = row["timestamp"]
                position = {
                    "entry_price": entry_price,
                    "units": units,
                    "entry_timestamp": entry_timestamp,
                }
                logging.info(f"Buy at {entry_price} on {entry_timestamp}")
            # Sell signal
            elif (
                row["high"] >= sell_zone
                and row["close"] < sell_zone
                and position is not None
            ):
                exit_price = row["close"]
                exit_timestamp = row["timestamp"]
                profit = (exit_price - position["entry_price"]) * position["units"]
                self.balance += profit  # Update balance
                trade = {
                    "entry_price": position["entry_price"],
                    "entry_timestamp": position["entry_timestamp"],
                    "exit_price": exit_price,
                    "exit_timestamp": exit_timestamp,
                    "profit": profit,
                    "units": position["units"],
                }
                self.trades.append(trade)
                self.equity_curve.append(
                    {"timestamp": exit_timestamp, "balance": self.balance}
                )
                logging.info(
                    f"Sell at {exit_price} on {exit_timestamp} - Profit: {profit}"
                )
                position = None  # Reset position

        # Handle any open position at the end
        if position is not None:
            exit_price = self.data["close"].iloc[-1]
            exit_timestamp = self.data["timestamp"].iloc[-1]
            profit = (exit_price - position["entry_price"]) * position["units"]
            self.balance += profit
            trade = {
                "entry_price": position["entry_price"],
                "entry_timestamp": position["entry_timestamp"],
                "exit_price": exit_price,
                "exit_timestamp": exit_timestamp,
                "profit": profit,
                "units": position["units"],
            }
            self.trades.append(trade)
            self.equity_curve.append(
                {"timestamp": exit_timestamp, "balance": self.balance}
            )
            logging.info(
                f"Closing remaining position at {exit_price} on {exit_timestamp} - Profit: {profit}"
            )
            position = None

        # Final balance and metrics
        logging.info(f"Final Balance: {self.balance}")
        self.calculate_backtest_metrics()

    def calculate_backtest_metrics(self):
        """Calculate and print key performance metrics."""
        net_profit = self.balance - self.initial_balance
        total_trades = len(self.trades)
        winning_trades = [trade for trade in self.trades if trade["profit"] > 0]
        losing_trades = [trade for trade in self.trades if trade["profit"] <= 0]
        win_rate = len(winning_trades) / total_trades * 100 if total_trades > 0 else 0
        avg_profit = net_profit / total_trades if total_trades > 0 else 0
        max_drawdown = self.calculate_max_drawdown()

        logging.info(f"Net Profit: {net_profit}")
        logging.info(f"Total Trades: {total_trades}")
        logging.info(f"Win Rate: {win_rate:.2f}%")
        logging.info(f"Average Profit per Trade: {avg_profit}")
        logging.info(f"Max Drawdown: {max_drawdown:.2f}%")

    def calculate_max_drawdown(self):
        """Calculate maximum drawdown."""
        balances = [point["balance"] for point in self.equity_curve]
        peak = balances[0]
        max_drawdown = 0
        for balance in balances:
            if balance > peak:
                peak = balance
            drawdown = (peak - balance) / peak
            if drawdown > max_drawdown:
                max_drawdown = drawdown
        return max_drawdown * 100  # as percentage

    def plot_results(self):
        """Plot backtesting results."""
        df_trades = pd.DataFrame(self.trades)
        plt.figure(figsize=(12, 6))
        plt.plot(
            self.data["timestamp"], self.data["close"], label="Price", color="blue"
        )
        if not df_trades.empty:
            buys = df_trades[["entry_timestamp", "entry_price"]].drop_duplicates()
            sells = df_trades[["exit_timestamp", "exit_price"]].drop_duplicates()
            plt.scatter(
                buys["entry_timestamp"],
                buys["entry_price"],
                label="Buy",
                marker="^",
                color="green",
            )
            plt.scatter(
                sells["exit_timestamp"],
                sells["exit_price"],
                label="Sell",
                marker="v",
                color="red",
            )
        plt.legend()
        plt.title("Backtest Results")
        plt.xlabel("Timestamp")
        plt.ylabel("Price")
        plt.show()

        # Plot equity curve
        df_equity = pd.DataFrame(self.equity_curve)
        plt.figure(figsize=(12, 6))
        plt.plot(
            df_equity["timestamp"],
            df_equity["balance"],
            label="Equity Curve",
            color="purple",
        )
        plt.legend()
        plt.title("Equity Curve")
        plt.xlabel("Timestamp")
        plt.ylabel("Balance")
        plt.show()
        
if __name__ == "__main__":
    # Define configuration parameters directly in the script
    exchange_name = "bybit"
    api_key = "your_api_key"
    api_secret = "your_api_secret"
    symbol = "BTC/USDT"
    timeframe = "15m"
    limit = 1000
    initial_balance = 10000
    position_size = 1.0  # Use 1.0 for 100% of the balance

    bot = TradingBot(
        exchange_name=exchange_name,
        api_key=api_key,
        api_secret=api_secret,
        symbol=symbol,
        timeframe=timeframe,
        limit=limit,
        initial_balance=initial_balance,
        position_size=position_size,
    )
    bot.backtest()
    bot.plot_results()
