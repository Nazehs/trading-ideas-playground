import numpy as np
import pandas as pd
from sklearn.preprocessing import StandardScaler
import plotly.graph_objects as go
from hmmlearn import hmm
from typing import List, Tuple, Dict
import matplotlib.pyplot as plt
import seaborn as sns
from sklearn.cluster import KMeans
import ta
from ta.trend import SMAIndicator, EMAIndicator, MACD
from ta.momentum import RSIIndicator, StochasticOscillator
from ta.volatility import BollingerBands, AverageTrueRange
from ta.volume import OnBalanceVolumeIndicator, VolumePriceTrendIndicator


class ForexHMMTrader:
    def __init__(self, n_regimes: int = 3):
        self.n_regimes = n_regimes
        self.models = {}
        self.scalers = {}
        self.selected_features = []

    def add_technical_indicators(self, df: pd.DataFrame) -> pd.DataFrame:
        """Add technical indicators using the TA library."""
        df = df.copy()

        # Trend Indicators
        df["SMA_20"] = SMAIndicator(close=df["Close"], window=20).sma_indicator()
        df["SMA_50"] = SMAIndicator(close=df["Close"], window=50).sma_indicator()
        df["EMA_20"] = EMAIndicator(close=df["Close"], window=20).ema_indicator()

        macd = MACD(close=df["Close"])
        df["MACD"] = macd.macd()
        df["MACD_Signal"] = macd.macd_signal()
        df["MACD_Diff"] = macd.macd_diff()

        # Momentum Indicators
        df["RSI"] = RSIIndicator(close=df["Close"]).rsi()

        stoch = StochasticOscillator(high=df["High"], low=df["Low"], close=df["Close"])
        df["Stoch_K"] = stoch.stoch()
        df["Stoch_D"] = stoch.stoch_signal()

        # Volatility Indicators
        bb = BollingerBands(close=df["Close"])
        df["BB_High"] = bb.bollinger_hband()
        df["BB_Low"] = bb.bollinger_lband()
        df["BB_Mid"] = bb.bollinger_mavg()
        df["BB_Width"] = bb.bollinger_wband()

        df["ATR"] = AverageTrueRange(
            high=df["High"], low=df["Low"], close=df["Close"]
        ).average_true_range()

        # Price-based features
        df["Returns"] = df["Close"].pct_change()
        df["Log_Returns"] = np.log1p(df["Returns"])

        # Volume-based Indicators (if volume is available)
        if "Volume" in df.columns:
            df["OBV"] = OnBalanceVolumeIndicator(
                close=df["Close"], volume=df["Volume"]
            ).on_balance_volume()
            df["VPT"] = VolumePriceTrendIndicator(
                close=df["Close"], volume=df["Volume"]
            ).volume_price_trend()

        return df

    def select_features(self, df: pd.DataFrame) -> np.ndarray:
        """Select and prepare features for the HMM."""
        core_features = [
            "Returns",
            "Log_Returns",
            "RSI",
            "MACD_Diff",
            "BB_Width",
            "ATR",
        ]
        trend_features = ["SMA_20", "SMA_50", "EMA_20"]
        momentum_features = ["Stoch_K", "Stoch_D"]

        self.selected_features = core_features + trend_features + momentum_features
        if "Volume" in df.columns:
            self.selected_features.extend(["OBV", "VPT"])

        # Prepare feature matrix
        feature_matrix = []
        for feature in self.selected_features:
            scaler = StandardScaler()
            scaled_feature = scaler.fit_transform(df[feature].values.reshape(-1, 1))
            feature_matrix.append(scaled_feature)
            self.scalers[feature] = scaler

        return np.hstack(feature_matrix)

    def preprocess_data(self, df: pd.DataFrame) -> Tuple[np.ndarray, pd.DataFrame]:
        """Preprocess the forex data."""
        # Add technical indicators
        df_indicators = self.add_technical_indicators(df)

        # Select features and create feature matrix
        X = self.select_features(df_indicators)

        # Remove NaN values
        valid_idx = ~np.isnan(X).any(axis=1)
        X = X[valid_idx]
        df_processed = df_indicators[valid_idx].reset_index(drop=True)

        return X, df_processed

    def identify_market_regimes(self, X: np.ndarray) -> np.ndarray:
        """Identify market regimes using K-means clustering."""
        kmeans = KMeans(n_clusters=self.n_regimes, random_state=42)
        return kmeans.fit_predict(X)

    def create_curriculum(self, X: np.ndarray, regimes: np.ndarray) -> List[np.ndarray]:
        """Create curriculum stages for training."""
        curriculum_stages = []

        # Stage 1: Single regime data
        for regime in range(self.n_regimes):
            regime_data = X[regimes == regime]
            curriculum_stages.append(regime_data)

        # Stage 2: Pairwise regime combinations
        for i in range(self.n_regimes):
            for j in range(i + 1, self.n_regimes):
                combined_data = np.vstack([X[regimes == i], X[regimes == j]])
                curriculum_stages.append(combined_data)

        # Stage 3: All regimes
        curriculum_stages.append(X)

        return curriculum_stages

    def train_curriculum(self, curriculum_stages: List[np.ndarray]):
        """Train HMM models on curriculum stages."""
        for stage, data in enumerate(curriculum_stages):
            model = hmm.GaussianHMM(
                n_components=self.n_regimes,
                covariance_type="full",
                n_iter=600,
                random_state=42,
            )
            model.fit(data)
            self.models[f"stage_{stage}"] = model

        # Train a final model on all data
        final_model = hmm.GaussianHMM(
            n_components=self.n_regimes,
            covariance_type="full",
            n_iter=600,
            random_state=42,
        )
        final_model.fit(np.vstack(curriculum_stages))  # Fit on all stages combined
        self.models["stage_final"] = final_model

    def predict_regime(self, X: np.ndarray, stage: str = "stage_final") -> np.ndarray:
        """Predict market regimes using the trained HMM."""
        if stage not in self.models:
            raise ValueError(
                f"Model for stage '{stage}' not found. Available stages: {list(self.models.keys())}"
            )

        model = self.models[stage]
        return model.predict(X)

    def calculate_regime_probabilities(
        self, X: np.ndarray, stage: str = "stage_final"
    ) -> np.ndarray:
        """Calculate probabilities for each regime."""
        model = self.models[stage]
        return model.predict_proba(X)

    def generate_trading_signals(
        self, regime_probs: np.ndarray, threshold: float = 0.7
    ) -> np.ndarray:
        """Generate trading signals based on regime probabilities and additional indicators."""
        signals = np.zeros(len(regime_probs))

        for i in range(len(regime_probs)):
            max_prob = np.max(regime_probs[i])
            max_regime = np.argmax(regime_probs[i])

            if max_prob > threshold:
                if max_regime == 2:  # Bearish regime
                    signals[i] = 1  # Sell signal
                elif max_regime == 1:  # Bullish regime
                    signals[i] = -1  # Buy signal
                # Regime 1 is neutral

        return signals

    def backtest_strategy(self, df: pd.DataFrame, signals: np.ndarray) -> pd.DataFrame:
        """Backtest the trading strategy."""
        df = df.copy()
        df["Signal"] = signals
        df["Returns"] = df["Close"].pct_change()
        df["Strategy_Returns"] = df["Signal"].shift(1) * df["Returns"]

        df["Cumulative_Returns"] = (1 + df["Returns"]).cumprod()
        df["Strategy_Cumulative_Returns"] = (1 + df["Strategy_Returns"]).cumprod()

        return df

    def plot_regime_transitions(self, regimes: np.ndarray, df: pd.DataFrame):
        """Plot price with regime transitions using Plotly."""
        fig = go.Figure()

        # Add price trace
        fig.add_trace(
            go.Scatter(
                x=df.index,
                y=df["Close"],
                mode="lines",
                name="Price",
                line=dict(color="blue", width=2),
                opacity=0.7,
            )
        )

        # Add regime traces
        colors = ["red", "black", "green"]
        for regime in range(self.n_regimes):
            regime_data = df["Close"].copy()
            regime_data[regimes != regime] = np.nan
            fig.add_trace(
                go.Scatter(
                    x=df.index,
                    y=regime_data,
                    mode="lines",
                    name=f"Regime {regime}",
                    line=dict(color=colors[regime]),
                    opacity=0.5,
                )
            )

        # Update layout for better visualization
        fig.update_layout(
            title="Forex Price with Market Regimes",
            xaxis_title="Time",
            yaxis_title="Price",
            legend_title="Regimes",
            hovermode="x unified",
        )

        # Show the figure
        fig.show()

    def plot_feature_importance(self, X: np.ndarray, stage: str = "stage_final"):
        """Plot feature importance based on HMM parameters."""
        model = self.models[stage]
        means = model.means_
        covars = model.covars_

        importance_scores = np.zeros(len(self.selected_features))
        for i in range(self.n_regimes):
            importance_scores += np.abs(means[i]) / np.sqrt(np.diag(covars[i]))

        importance_df = pd.DataFrame(
            {"Feature": self.selected_features, "Importance": importance_scores}
        )
        importance_df = importance_df.sort_values("Importance", ascending=False)

        plt.figure(figsize=(20, 16))
        sns.barplot(x="Importance", y="Feature", data=importance_df)
        plt.title("Feature Importance")
        plt.tight_layout()
        plt.show()


def main():
    # Load your forex data
    df = pd.read_csv("currency_hourly_data.csv")
    # drop nan and zero values
    df = df.dropna()
    df = df[df["Close"] != 0]

    # Initialize and train the model
    trader = ForexHMMTrader(n_regimes=3)
    X, processed_df = trader.preprocess_data(df)

    # Identify initial regimes
    regimes = trader.identify_market_regimes(X)

    # Create and train curriculum
    curriculum_stages = trader.create_curriculum(X, regimes)
    trader.train_curriculum(curriculum_stages)

    # Generate trading signals
    final_regimes = trader.predict_regime(X)
    regime_probs = trader.calculate_regime_probabilities(X)
    signals = trader.generate_trading_signals(regime_probs)

    # Backtest strategy
    results = trader.backtest_strategy(processed_df, signals)

    # Plot results
    trader.plot_regime_transitions(final_regimes, processed_df)
    trader.plot_feature_importance(X)

    # Plot strategy performance
    plt.figure(figsize=(20, 16))
    plt.plot(results["Cumulative_Returns"], label="Buy and Hold")
    plt.plot(results["Strategy_Cumulative_Returns"], label="HMM Strategy")
    plt.title("Strategy Performance")
    plt.xlabel("Time")
    plt.ylabel("Cumulative Returns")
    plt.legend()
    plt.show()

    return trader, results


if __name__ == "__main__":
    trader, results = main()
