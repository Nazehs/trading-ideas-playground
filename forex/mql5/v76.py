import pandas as pd
import numpy as np
import gym
import pandas_ta as ta
from stable_baselines3 import PPO
from stable_baselines3.common.vec_env import DummyVecEnv
from stable_baselines3.common.vec_env import VecNormalize
from sklearn.model_selection import train_test_split
import quantstats as qs


# Step 1: Load and clean the data
def load_and_clean_data(filepath):
    dtype_dict = {
        0: str,  # Ticker
        1: str,  # Date
        2: str,  # Time
        3: str,  # Open
        4: str,  # High
        5: str,  # Low
        6: str,  # Close
        7: str,  # TickVol
        8: str,  # Vol
    }

    # Read the file and clean the data
    data = pd.read_csv(
        filepath,
        sep="\t",
        header=None,
        names=[
            "Date",
            "Time",
            "Open",
            "High",
            "Low",
            "Close",
            "TickVol",
            "Vol",
            "Spread",
        ],
        dtype=dtype_dict,
        low_memory=False,
    )

    # Clean numeric columns
    numeric_cols = ["Open", "High", "Low", "Close", "TickVol", "Vol", "Spread"]
    data[numeric_cols] = data[numeric_cols].apply(pd.to_numeric, errors="coerce")

    # Drop rows with NaN values in essential columns
    data.dropna(subset=["Open", "High", "Low", "Close"], inplace=True)

    # Combine Date and Time into a single datetime column
    data["Datetime"] = pd.to_datetime(
        data["Date"].astype(str) + " " + data["Time"].astype(str)
    )

    # Set Datetime as index
    data.set_index("Datetime", inplace=True)

    # Drop the original Date and Time columns
    data.drop(columns=["Date", "Time"], inplace=True)

    return data


# Step 2: Add technical indicators for feature engineering
def add_technical_indicators(data):
    # Ensure enough data for indicators
    if len(data) < 26:
        raise ValueError(
            "Not enough data to calculate MACD. At least 26 rows are required."
        )

    # Add RSI
    data["RSI"] = RSI(data["Close"]).fillna(0)

    # Add Moving Averages
    data["SMA_10"] = data["Close"].rolling(window=10).mean().fillna(0)
    data["EMA_10"] = data["Close"].ewm(span=10, adjust=False).mean().fillna(0)

    # Add MACD
    data["EMA_12"] = data["Close"].ewm(span=12, adjust=False).mean().fillna(0)
    data["EMA_26"] = data["Close"].ewm(span=26, adjust=False).mean().fillna(0)
    data["MACD"] = data["EMA_12"] - data["EMA_26"]

    # Add Bollinger Bands
    data["BB_Middle"] = data["Close"].rolling(window=20).mean().fillna(0)
    data["BB_Upper"] = data["BB_Middle"] + 2 * data["Close"].rolling(
        window=20
    ).std().fillna(0)
    data["BB_Lower"] = data["BB_Middle"] - 2 * data["Close"].rolling(
        window=20
    ).std().fillna(0)

    return data


# Helper function to calculate RSI
def RSI(series, period=14):
    delta = series.diff()
    gain = (delta.where(delta > 0, 0)).rolling(window=period).mean()
    loss = (-delta.where(delta < 0, 0)).rolling(window=period).mean()
    RS = gain / loss
    return 100 - (100 / (1 + RS))


# Load and preprocess the data
data = load_and_clean_data("Vix75.csv")
print(data.info())
test_data = load_and_clean_data("vixy.csv")

# Add technical indicators
data = add_technical_indicators(data)
print(data.head())


# Step 3: Create custom trading environment
class TradingEnv(gym.Env):
    def __init__(self, data):
        super(TradingEnv, self).__init__()
        self.data = data
        self.current_step = 0
        self.action_space = gym.spaces.Discrete(3)  # Buy, Hold, Sell

        # Define observation space explicitly
        self.observation_space = gym.spaces.Box(
            low=-np.inf, high=np.inf, shape=(data.shape[1],), dtype=np.float32
        )

        self.balance = 10000  # Initial balance
        self.position = 0  # No position (1 = Long, -1 = Short)
        self.entry_price = 0
        self.penalty = -0.002  # Penalty for losing trades
        self.reward_multiplier = 0.01  # Reward multiplier for profits

    def reset(self):
        self.current_step = 0
        self.balance = 10000
        self.position = 0
        self.entry_price = 0

        # Check if the dataset has enough rows
        if len(self.data) == 0:
            raise ValueError("The data is empty. Unable to reset the environment.")

        # Ensure current_step is within valid range
        if self.current_step >= len(self.data):
            raise IndexError(
                "Initial step is out of bounds, check the size of your data."
            )

        return self.data.iloc[self.current_step].values

    def step(self, action):
        # Ensure current_step is within valid range
        if self.current_step >= len(self.data):
            raise IndexError("Step is out of bounds, check the size of your data.")

        current_price = self.data.iloc[self.current_step]["Close"]
        reward = 0

        if action == 0:  # Buy
            if self.position == 0:
                self.position = 1
                self.entry_price = current_price
        elif action == 2:  # Sell
            if self.position == 1:
                profit = current_price - self.entry_price
                reward = (
                    self.reward_multiplier * profit
                    if profit > 0
                    else self.penalty * abs(profit)
                )
                self.balance += self.reward_multiplier * profit
                self.position = 0

        # Penalty for holding too long or having no position
        reward -= 0.001 * abs(self.position)

        # Move to the next step
        self.current_step += 1

        # Check if we're at the end of the data
        done = self.current_step >= len(self.data) - 1

        # Ensure valid observation
        if done:
            obs = self.data.iloc[
                -1
            ].values  # Return the last valid observation when done
        else:
            obs = self.data.iloc[self.current_step].values

        return obs, reward, done, {}

    def render(self, mode="human"):
        print(
            f"Step: {self.current_step}, Balance: {self.balance}, Position: {self.position}"
        )


# Step 4: Wrap the environment with DummyVecEnv and VecNormalize
env = DummyVecEnv([lambda: TradingEnv(data)])  # Dummy vectorized environment
env = VecNormalize(env, norm_obs=True, norm_reward=True)


# Step 5: Train the PPO model with default hyperparameters
model = PPO(
    "MlpPolicy",
    env,
    verbose=1,
    policy_kwargs=dict(net_arch=[dict(pi=[64, 64], vf=[64, 64])]),
    learning_rate=3e-4,  # Default value
    n_steps=2048,  # Default value
    batch_size=64,  # Default value
    gamma=0.99,  # Default value
    gae_lambda=0.95,  # Default value
    clip_range=0.2,  # Default value
)

# Train the model
model.learn(total_timesteps=100000)
model.save("ppo_15m_VIX75_model")


# Step 6: Model evaluation using Quantstats
def evaluate_rl_model(model, test_data):
    env = DummyVecEnv([lambda: TradingEnv(test_data)])  # Wrap test env
    obs = env.reset()
    total_reward = 0
    rewards = []
    done = False
    step = 0
    dates = test_data.index  # Get the index (dates) from test_data

    while not done:
        action, _states = model.predict(obs)
        obs, reward, done, _ = env.step(action)
        total_reward += reward[0]  # Extract scalar reward from the array
        rewards.append(
            reward[0]
        )  # Make sure reward is a scalar value (as VecEnv returns it in a list)
        step += 1

    # Create a rewards series with the test data's index (DatetimeIndex)
    rewards_series = pd.Series(
        rewards, index=dates[: len(rewards)]
    )  # Align rewards with dates

    # Calculate cumulative returns from rewards
    returns = (
        rewards_series.cumsum() / 10000
    )  # Assuming initial balance is 10000 for normalization

    # Ensure that the returns are correctly formatted and have the same length
    returns = returns[
        : len(test_data)
    ]  # Ensure the length matches the test data length

    # Use quantstats to generate report
    qs.reports.html(returns, output="report_VIX75.html", title="RL Trading Strategy")

    return total_reward


# Step 7: Load test data and evaluate the model
# train_data, test_data = train_test_split(data, test_size=0.2, shuffle=False)
total_reward = evaluate_rl_model(model, test_data)
print(f"Total reward: {total_reward}")
