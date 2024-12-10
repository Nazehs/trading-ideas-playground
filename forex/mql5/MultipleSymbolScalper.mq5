//+------------------------------------------------------------------+
//|                                                  ScalpingBot.mq5 |
//|                            Copyright 2024, Open lab technologies |
//|                              https://www.openlabtechnologies.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Open lab technologies"
#property link "https://www.openlabtechnologies.com"
#property version "1.01"

#include <Trade\Trade.mqh>
#include <Trade\OrderInfo.mqh>

CTrade trade;				// Object for trade operations
CPositionInfo positionInfo; // Object for position information
COrderInfo orderInfo;		// Object for order information

//+------------------------------------------------------------------+
//| Enums                                                            |
//+------------------------------------------------------------------+
enum StartHour
{
	Inactive = 0,
	_0000,
	_0100,
	_0200,
	_0300,
	_0400,
	_0500,
	_0600,
	_0700,
	_0800,
	_0900,
	_1000,
	_1100,
	_1200,
	_1300,
	_1400,
	_1500,
	_1600,
	_1700,
	_1800,
	_1900,
	_2000,
	_2100,
	_2200,
	_2300
};

enum EndHour
{
	Inactive = 0,
	_0000,
	_0100,
	_0200,
	_0300,
	_0400,
	_0500,
	_0600,
	_0700,
	_0800,
	_0900,
	_1000,
	_1100,
	_1200,
	_1300,
	_1400,
	_1500,
	_1600,
	_1700,
	_1800,
	_1900,
	_2000,
	_2100,
	_2200,
	_2300
};

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
input group "===== Risk Management ====" input double riskPercentage = 2.0; // Risk percentage for position sizing
input double DrawdownPercent = 5.0;											// Drawdown percentage threshold
input bool useDrawdownPercent = false;										// Enable drawdown percent
input int maxTrades = 5;													// Maximum number of trades allowed at a time
input int maxTotalTrades = 10;												// Maximum total number of trades across all assets
input int maxBuyOrdersPerSymbol = 3;										// Maximum number of buy orders allowed per symbol
input int maxSellOrdersPerSymbol = 3;										// Maximum number of sell orders allowed per symbol

input group "===== Order Management ====" input int MagicNumber = 13; // Magic number for identifying trades
input string tradeComment = "";										  // Comment for trades

//+------------------------------------------------------------------+
//| Input Parameters for News Integration                            |
//+------------------------------------------------------------------+
input bool enableNewsIntegration = true; // Enable or disable news integration

//+------------------------------------------------------------------+
//| Asset Configuration Structure                                     |
//+------------------------------------------------------------------+
struct AssetConfig
{
	string symbol;
	bool enabled;
	double takeProfitPercentage;
	double stopLossPercentage;
	double trailingStopLossAsPercentOfTP;
	double trailingStopLossTriggerAsPercentOfTP;
	double orderDistancePoints;
	int expirationBars;
	int numberOfCandlesRange;
	int barsToLookBack;
	StartHour startHour;
	EndHour endHour;
	ENUM_TIMEFRAMES timeframe;
};

//+------------------------------------------------------------------+
//| Asset-Specific Input Parameters                                  |
//+------------------------------------------------------------------+

input group "==== BTCUSD Parameters ====" input bool BTCUSDm_Enabled = true; // Enable BTCUSD trading
input double BTCUSDm_TakeProfitPercentage = 0.2;							 // TP percentage for BTCUSD
input double BTCUSDm_StopLossPercentage = 0.2;								 // SL percentage for BTCUSD
input double BTCUSDm_TrailingStopLossAsPercentOfTP = 5;						 // Trailing SL as a percentage of TP for BTCUSD
input double BTCUSDm_TrailingStopLossTriggerAsPercentOfTP = 7;				 // Trailing SL trigger as a percentage of TP for BTCUSD
input double BTCUSDm_OrderDistancePoints = 100;								 // Minimum distance in points for placing orders for BTCUSD
input int BTCUSDm_ExpirationBars = 100;										 // Number of bars after which the order expires for BTCUSD
input int BTCUSDm_NumberOfCandlesRange = 200;								 // Number of candles to consider for high/low search for BTCUSD
input int BTCUSDm_BarsToLookBack = 5;										 // Number of bars to look back for swing high/low for BTCUSD
input StartHour BTCUSDm_StartHour = 0;										 // Start hour for trading BTCUSD
input EndHour BTCUSDm_EndHour = 0;											 // End hour for trading BTCUSD
input ENUM_TIMEFRAMES BTCUSDm_Timeframe = PERIOD_CURRENT;					 // BTCUSD timeframe input

input group "==== US30 Parameters ====" input bool US30m_Enabled = true; // Enable US30 trading
input double US30m_TakeProfitPercentage = 0.2;							 // TP percentage for US30
input double US30m_StopLossPercentage = 0.2;							 // SL percentage for US30
input double US30m_TrailingStopLossAsPercentOfTP = 5;					 // Trailing SL as a percentage of TP for US30
input double US30m_TrailingStopLossTriggerAsPercentOfTP = 7;			 // Trailing SL trigger as a percentage of TP for US30
input double US30m_OrderDistancePoints = 100;							 // Minimum distance in points for placing orders for US30
input int US30m_ExpirationBars = 100;									 // Number of bars after which the order expires for US30
input int US30m_NumberOfCandlesRange = 200;								 // Number of candles to consider for high/low search for US30
input int US30m_BarsToLookBack = 5;										 // Number of bars to look back for swing high/low for US30
input StartHour US30m_StartHour = 0;									 // Start hour for trading US30
input EndHour US30m_EndHour = 0;										 // End hour for trading US30
input ENUM_TIMEFRAMES US30m_Timeframe = PERIOD_CURRENT;					 // US30 trading timeframe

input group "==== US100 Parameters ====" input bool US100m_Enabled = true;	 // Enable US100 trading
input double US100m_TakeProfitPercentage = 0.2;								 // TP percentage for US100
input double US100m_StopLossPercentage = 0.2;								 // SL percentage for US100
input double US100m_TrailingStopLossAsPercentOfTP = 5;						 // Trailing SL as a percentage of TP for US100
input double US100m_TrailingStopLossTriggerAsPercentOfTP = 7;				 // Trailing SL trigger as a percentage of TP for US100
input double US100m_OrderDistancePoints = 100;								 // Minimum distance in points for placing orders for US100
input int US100m_ExpirationBars = 100;										 // Number of bars after which the order expires for US100
input int US100m_NumberOfCandlesRange = 200;								 // Number of candles to consider for high/low search for US100
input int US100m_BarsToLookBack = 5;										 // Number of bars to look back for swing high/low for US100
input StartHour US100m_StartHour = 0;										 // Start hour for trading US100
input EndHour US100m_EndHour = 0;											 // End hour for trading US100
input ENUM_TIMEFRAMES US100m_Timeframe = PERIOD_CURRENT;					 // US100 trading timeframe
input group "==== GBPUSD Parameters ====" input bool GBPUSDm_Enabled = true; // Enable GBPUSD trading
input double GBPUSDm_TakeProfitPercentage = 0.2;							 // TP percentage for GBPUSD
input double GBPUSDm_StopLossPercentage = 0.2;								 // SL percentage for GBPUSD
input double GBPUSDm_TrailingStopLossAsPercentOfTP = 5;						 // Trailing SL as a percentage of TP for GBPUSD
input double GBPUSDm_TrailingStopLossTriggerAsPercentOfTP = 7;				 // Trailing SL trigger as a percentage of TP for GBPUSD
input double GBPUSDm_OrderDistancePoints = 100;								 // Minimum distance in points for placing orders for GBPUSD
input int GBPUSDm_ExpirationBars = 100;										 // Number of bars after which the order expires for GBPUSD
input int GBPUSDm_NumberOfCandlesRange = 200;								 // Number of candles to consider for high/low search for GBPUSD
input int GBPUSDm_BarsToLookBack = 5;										 // Number of bars to look back for swing high/low for GBPUSD
input StartHour GBPUSDm_StartHour = 0;										 // Start hour for trading GBPUSD
input EndHour GBPUSDm_EndHour = 0;											 // End hour for trading GBPUSD
input ENUM_TIMEFRAMES GBPUSDm_Timeframe = PERIOD_CURRENT;					 // GBPUSD trading timeframe
input group "==== XAUUSD Parameters ====" input bool XAUUSDm_Enabled = true; // Enable XAUUSD trading
input double XAUUSDm_TakeProfitPercentage = 0.2;							 // TP percentage for XAUUSD
input double XAUUSDm_StopLossPercentage = 0.2;								 // SL percentage for XAUUSD
input double XAUUSDm_TrailingStopLossAsPercentOfTP = 5;						 // Trailing SL as a percentage of TP for XAUUSD
input double XAUUSDm_TrailingStopLossTriggerAsPercentOfTP = 7;				 // Trailing SL trigger as a percentage of TP for XAUUSD
input double XAUUSDm_OrderDistancePoints = 100;								 // Minimum distance in points for placing orders for XAUUSD
input int XAUUSDm_ExpirationBars = 100;										 // Number of bars after which the order expires for XAUUSD
input int XAUUSDm_NumberOfCandlesRange = 200;								 // Number of candles to consider for high/low search for XAUUSD
input int XAUUSDm_BarsToLookBack = 5;										 // Number of bars to look back for swing high/low for XAUUSD
input StartHour XAUUSDm_StartHour = 0;										 // Start hour for trading XAUUSD
input EndHour XAUUSDm_EndHour = 0;											 // End hour for trading XAUUSD
input ENUM_TIMEFRAMES XAUUSDm_Timeframe = PERIOD_CURRENT;					 // XAUUSD trading timeframe
//+------------------------------------------------------------------+
//| News Event Structure                                             |
//+------------------------------------------------------------------+
struct NewsEvent
{
	datetime time;
	string currency;
	string impact;
};

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
AssetConfig assetConfigs[] = {
	{"BTCUSDm", BTCUSDm_Enabled, BTCUSDm_TakeProfitPercentage, BTCUSDm_StopLossPercentage, BTCUSDm_TrailingStopLossAsPercentOfTP, BTCUSDm_TrailingStopLossTriggerAsPercentOfTP, BTCUSDm_OrderDistancePoints, BTCUSDm_ExpirationBars, BTCUSDm_NumberOfCandlesRange, BTCUSDm_BarsToLookBack, BTCUSDm_StartHour, BTCUSDm_EndHour, BTCUSDm_Timeframe},
	{"US30m", US30m_Enabled, US30m_TakeProfitPercentage, US30m_StopLossPercentage, US30m_TrailingStopLossAsPercentOfTP, US30m_TrailingStopLossTriggerAsPercentOfTP, US30m_OrderDistancePoints, US30m_ExpirationBars, US30m_NumberOfCandlesRange, US30m_BarsToLookBack, US30m_StartHour, US30m_EndHour, US30m_Timeframe},
	{"US100m", US100m_Enabled, US100m_TakeProfitPercentage, US100m_StopLossPercentage, US100m_TrailingStopLossAsPercentOfTP, US100m_TrailingStopLossTriggerAsPercentOfTP, US100m_OrderDistancePoints, US100m_ExpirationBars, US100m_NumberOfCandlesRange, US100m_BarsToLookBack, US100m_StartHour, US100m_EndHour, US100m_Timeframe},
	{"GBPUSDm", GBPUSDm_Enabled, GBPUSDm_TakeProfitPercentage, GBPUSDm_StopLossPercentage, GBPUSDm_TrailingStopLossAsPercentOfTP, GBPUSDm_TrailingStopLossTriggerAsPercentOfTP, GBPUSDm_OrderDistancePoints, GBPUSDm_ExpirationBars, GBPUSDm_NumberOfCandlesRange, GBPUSDm_BarsToLookBack, GBPUSDm_StartHour, GBPUSDm_EndHour, GBPUSDm_Timeframe},
	{"XAUUSDm", XAUUSDm_Enabled, XAUUSDm_TakeProfitPercentage, XAUUSDm_StopLossPercentage, XAUUSDm_TrailingStopLossAsPercentOfTP, XAUUSDm_TrailingStopLossTriggerAsPercentOfTP, XAUUSDm_OrderDistancePoints, XAUUSDm_ExpirationBars, XAUUSDm_NumberOfCandlesRange, XAUUSDm_BarsToLookBack, XAUUSDm_StartHour, XAUUSDm_EndHour, XAUUSDm_Timeframe}};

NewsEvent newsEvents[]; // Array to hold news events

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
	// Validate that the sum of max buy and sell orders per symbol does not exceed max total trades
	if (maxBuyOrdersPerSymbol + maxSellOrdersPerSymbol > maxTotalTrades)
	{
		Print("Error: The sum of maxBuyOrdersPerSymbol and maxSellOrdersPerSymbol exceeds maxTotalTrades.");
		return INIT_FAILED; // Initialization failed
	}

	//--- create timer
	trade.LogLevel(LOG_LEVEL_ERRORS);			// Set logging level
	trade.SetExpertMagicNumber(MagicNumber);	// Set the magic number for trades
	ChartSetInteger(0, CHART_SHOW_GRID, false); // Hide grid lines
	// set the properties of the chart to be green on black
	ChartSetInteger(0, CHART_COLOR_BACKGROUND, clrWhite);
	ChartSetInteger(0, CHART_COLOR_CHART_UP, clrGreen);
	ChartSetInteger(0, CHART_COLOR_CHART_DOWN, clrRed);
	// set the chart to use candle stick style
	ChartSetInteger(0, CHART_MODE, CHART_CANDLES);

	// Initialize configurations for each asset
	for (int i = 0; i < ArraySize(assetConfigs); i++)
	{
		// we can add any initialization logic specific to each asset here
	}

	return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Manage trailing SL                                         |
//+------------------------------------------------------------------+
void ManageTrailingStop(string symbol, double trailingStopLossPoints, double trailingStopTriggerPoints)
{
	double trailingStop = trailingStopLossPoints * _Point; // Calculate trailing stop in price
	double currentPrice = NormalizeDouble(SymbolInfoDouble(symbol, SYMBOL_BID), _Digits);
	double currentAsk = NormalizeDouble(SymbolInfoDouble(symbol, SYMBOL_ASK), _Digits);
	// Iterate through all positions
	for (int i = PositionsTotal() - 1; i >= 0; i--)
	{
		// Select the position
		if (positionInfo.SelectByIndex(i))
		{
			ulong ticket = positionInfo.Ticket();
			double takeProfit = positionInfo.TakeProfit();
			double positionOpenPrice = positionInfo.PriceOpen();
			double currentStopLoss = positionInfo.StopLoss();
			// Only manage the buy positions for the current symbol
			if (positionInfo.Symbol() == symbol && positionInfo.PositionType() == POSITION_TYPE_BUY)
			{
				if (currentPrice - positionOpenPrice > (trailingStopTriggerPoints * _Point))
				{
					double newStopLoss = NormalizeDouble(currentPrice - trailingStop, _Digits);
					// Update SL only if it is higher than the current SL
					if (newStopLoss > currentStopLoss && newStopLoss != 0)
					{
						trade.PositionModify(ticket, newStopLoss, takeProfit);
					}
				}
			}
			else if (positionInfo.Symbol() == symbol && positionInfo.PositionType() == POSITION_TYPE_SELL)
			{
				if (currentAsk + (trailingStopTriggerPoints * _Point) < positionOpenPrice)
				{
					double newStopLoss = NormalizeDouble(currentAsk + trailingStop, _Digits);
					// Update SL only if it is lower than the current SL
					if (newStopLoss < currentStopLoss && newStopLoss != 0)
					{
						trade.PositionModify(ticket, newStopLoss, takeProfit);
					}
				}
			}
		}
	}
}

//+------------------------------------------------------------------+
//| Function to fetch news events using MQL5 economic calendar       |
//+------------------------------------------------------------------+
void FetchNewsEvents()
{
	if (!enableNewsIntegration)
	{
		Print("News integration is disabled.");
		return; // Exit if news integration is disabled
	}

	// Clear existing news events
	ArrayResize(newsEvents, 0);

	// Use the known country code for the United States
	string usCountryCode = "US"; // United States country code

	// Fetch events for the United States using the country code
	MqlCalendarEvent events[];
	int totalEvents = CalendarEventByCountry(usCountryCode, events);
	if (totalEvents > 0)
	{
		PrintFormat("US events: %d", totalEvents);
		ArrayPrint(events);
	}
	for (int i = 0; i < totalEvents; i++)
	{
		// Filter events based on importance or other criteria if needed
		if (events[i].importance == CALENDAR_IMPORTANCE_HIGH)
		{
			NewsEvent newsEvent;
			newsEvent.time = events[i].time_mode; // Assuming time_mode gives the event time
			newsEvent.currency = "USDm";		  // Example: Fetch events for USD
			newsEvent.impact = "High";			  // You can map the importance to a string if needed

			ArrayResize(newsEvents, ArraySize(newsEvents) + 1);
			newsEvents[ArraySize(newsEvents) - 1] = newsEvent;

			// Log the fetched news event
			PrintFormat("Fetched news event: Name=%s, TimeMode=%d, Currency=%s, Impact=%s, Source=%s",
						events[i].name,
						events[i].time_mode,
						newsEvent.currency,
						newsEvent.impact,
						events[i].source_url);
		}
	}
}

//+------------------------------------------------------------------+
//| Function to check for upcoming news events                       |
//+------------------------------------------------------------------+
bool IsNewsTime(string symbol)
{
	if (!enableNewsIntegration)
	{
		Print("News integration is disabled.");
		return false; // Exit if news integration is disabled
	}

	MqlDateTime currentTime;
	TimeToStruct(TimeCurrent(), currentTime);

	for (int i = 0; i < ArraySize(newsEvents); i++)
	{
		if (StringFind(symbol, newsEvents[i].currency) != -1)
		{
			// Check if the news event is within the next hour
			if (MathAbs(newsEvents[i].time - TimeCurrent()) < 3600)
			{
				PrintFormat("Upcoming news event for %s at %s",
							symbol,
							TimeToString(newsEvents[i].time, TIME_DATE | TIME_MINUTES));
				return true;
			}
		}
	}
	return false;
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
	// Fetch news events periodically
	static datetime lastFetchTime = 0;
	if (TimeCurrent() - lastFetchTime > 3600) // Fetch every hour
	{
		FetchNewsEvents();
		lastFetchTime = TimeCurrent();
	}

	// Count total trades across all assets
	int totalTrades = 0;
	for (int j = PositionsTotal() - 1; j >= 0; j--)
	{
		positionInfo.SelectByIndex(j);
		if (positionInfo.Magic() == MagicNumber)
		{
			totalTrades++;
		}
	}

	// Check if the total number of trades is less than the maximum allowed
	if (totalTrades >= maxTotalTrades)
	{
		PrintFormat("Maximum total number of trades (%d) reached", maxTotalTrades);
		return; // Exit if the total trade limit is reached
	}

	// Manage trailing SL for each asset
	for (int i = 0; i < ArraySize(assetConfigs); i++)
	{
		// Check if the asset is enabled
		if (!assetConfigs[i].enabled)
			continue; // Skip this asset if not enabled

		string currentSymbol = assetConfigs[i].symbol;

		// Check for upcoming news events
		if (IsNewsTime(currentSymbol))
		{
			PrintFormat("Skipping trading for %s due to upcoming news", currentSymbol);
			continue; // Skip trading for this symbol if news is upcoming
		}

		ENUM_TIMEFRAMES assetTimeframe = assetConfigs[i].timeframe;
		double takeProfitPoints = assetConfigs[i].takeProfitPercentage * SymbolInfoDouble(currentSymbol, SYMBOL_ASK);
		double stopLossPoints = assetConfigs[i].stopLossPercentage * SymbolInfoDouble(currentSymbol, SYMBOL_ASK);
		double trailingStopLossPoints = (assetConfigs[i].trailingStopLossAsPercentOfTP / 100) * takeProfitPoints;
		double trailingStopTriggerPoints = (assetConfigs[i].trailingStopLossTriggerAsPercentOfTP / 100) * takeProfitPoints;
		double orderDistancePoints = assetConfigs[i].orderDistancePoints;

		ManageTrailingStop(currentSymbol, trailingStopLossPoints, trailingStopTriggerPoints);

		if (useDrawdownPercent)
		{
			CloseTradesOnDrawdown();
		}
		if (!isNewBar(currentSymbol))
			continue; // Only execute logic on new bars

		MqlDateTime time;
		TimeToStruct(TimeCurrent(), time);			 // Get current time
		int currentHour = time.hour;				 // Get current hour
		if (currentHour < assetConfigs[i].startHour) // If before start hour for this symbol, close all orders
		{
			CloseAllOrders(currentSymbol);
			continue;
		}
		if (currentHour >= assetConfigs[i].endHour && assetConfigs[i].endHour != 0) // If after end hour for this symbol, close all orders
		{
			CloseAllOrders(currentSymbol);
			return;
		}

		int buyOrderTotal = 0;	// Count of existing buy orders
		int sellOrderTotal = 0; // Count of existing sell orders

		// Count current trades for the symbol
		for (int j = PositionsTotal() - 1; j >= 0; j--)
		{
			if (positionInfo.SelectByIndex(j) && positionInfo.Symbol() == currentSymbol && positionInfo.Magic() == MagicNumber)
			{
				if (positionInfo.PositionType() == POSITION_TYPE_BUY)
					buyOrderTotal++;
				else if (positionInfo.PositionType() == POSITION_TYPE_SELL)
					sellOrderTotal++;
			}
		}

		for (int i = OrdersTotal() - 1; i >= 0; i--)
		{
			if (orderInfo.SelectByIndex(i) && orderInfo.Symbol() == currentSymbol && orderInfo.Magic() == MagicNumber)
			{
				if (orderInfo.OrderType() == ORDER_TYPE_BUY_STOP)
					buyOrderTotal++;
				else if (orderInfo.OrderType() == ORDER_TYPE_SELL_STOP)
					sellOrderTotal++;
			}
		}

		// Check if the total number of trades for the symbol is less than the maximum allowed
		if (buyOrderTotal < maxBuyOrdersPerSymbol && totalTrades < maxTotalTrades) // Place a buy order if below max buy orders
		{
			double entryPrice = findHighs(currentSymbol, assetConfigs[i].numberOfCandlesRange, assetConfigs[i].barsToLookBack, assetTimeframe);
			PrintFormat("Current buy price return %.5f for %s", entryPrice, currentSymbol);
			if (entryPrice > 0)
			{
				SendBuyOrder(currentSymbol, entryPrice, stopLossPoints, takeProfitPoints, orderDistancePoints, assetConfigs[i].expirationBars);
				totalTrades++; // Increment total trades
			}
		}
		if (sellOrderTotal < maxSellOrdersPerSymbol && totalTrades < maxTotalTrades) // Place a sell order if below max sell orders
		{
			double entryPrice = findLows(currentSymbol, assetConfigs[i].numberOfCandlesRange, assetConfigs[i].barsToLookBack, assetTimeframe);
			PrintFormat("Current sell price return %.5f for %s", entryPrice, currentSymbol);
			if (entryPrice > 0)
			{
				SendSellOrder(currentSymbol, entryPrice, stopLossPoints, takeProfitPoints, orderDistancePoints, assetConfigs[i].expirationBars);
				totalTrades++; // Increment total trades
			}
		}
	}
}

//+------------------------------------------------------------------+
//| find the highest high within the last 'BarsN' bars               |
//+------------------------------------------------------------------+
double findHighs(string symbol, int candlesRange, int lookBackBars, ENUM_TIMEFRAMES assetTimeframe)
{
	double highestHigh = 0;
	for (int i = 0; i < candlesRange; i++)
	{
		double high = iHigh(symbol, assetTimeframe, i);
		if (i > lookBackBars && iHighest(symbol, assetTimeframe, MODE_HIGH, lookBackBars * 2 + 1, i - lookBackBars) == i)
		{
			if (high > highestHigh)
				return high;
		}
		highestHigh = MathMax(high, highestHigh);
	}
	return -1;
}

//+------------------------------------------------------------------+
//| find the lowest low within the last 'barsToLookBack' bars        |
//+------------------------------------------------------------------+
double findLows(string symbol, int candlesRange, int lookBackBars, ENUM_TIMEFRAMES assetTimeframe)
{
	double lowestLow = DBL_MAX;
	for (int i = 0; i < candlesRange; i++)
	{
		double low = iLow(symbol, assetTimeframe, i);
		if (i > lookBackBars && iLowest(symbol, assetTimeframe, MODE_LOW, lookBackBars * 2 + 1, i - lookBackBars) == i)
		{
			if (low < lowestLow)
				return low;
		}
		lowestLow = MathMin(low, lowestLow);
	}
	return -1;
}

//+------------------------------------------------------------------+
//| Check if a new bar has formed                                    |
//+------------------------------------------------------------------+
bool isNewBar(string symbol)
{
	static datetime lastTime = 0;
	ENUM_TIMEFRAMES assetTimeframe = GetAssetTimeframe(symbol);
	datetime currentTime = iTime(symbol, assetTimeframe, 0);
	if (currentTime != lastTime)
	{
		lastTime = currentTime;
		return true;
	}
	return false;
}

//+------------------------------------------------------------------+
//| Function to close all orders associated with the EA              |
//+------------------------------------------------------------------+
void CloseAllOrders(string symbol)
{
	for (int i = 0; i < OrdersTotal(); i++)
	{
		orderInfo.SelectByIndex(i);
		ulong ticket = orderInfo.Ticket();
		if (orderInfo.Symbol() == symbol && orderInfo.Magic() == MagicNumber)
		{
			trade.OrderDelete(ticket);
		}
	}
}

//+------------------------------------------------------------------+
//| Function to calculate the optimal lot size based on risk         |
//+------------------------------------------------------------------+
double lotSizeOptimization(string symbol, double stopLossPoints)
{
	double risk = AccountInfoDouble(ACCOUNT_BALANCE) * riskPercentage / 100;
	double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
	double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
	double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
	double minVolume = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
	double maxVolume = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
	double volumeLimit = SymbolInfoDouble(symbol, SYMBOL_VOLUME_LIMIT);
	double moneyPerLot = stopLossPoints / tickSize * tickValue * lotStep;
	double lots = MathFloor(risk / moneyPerLot) * lotStep;
	if (volumeLimit != 0)
		lots = MathMin(lots, volumeLimit);
	if (maxVolume != 0)
		lots = MathMin(lots, SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX));
	if (minVolume != 0)
	{
		lots = MathMax(lots, SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN));
	}
	lots = NormalizeDouble(lots, 2);
	return lots;
}

//+------------------------------------------------------------------+
//| Function to place a sell stop order                              |
//+------------------------------------------------------------------+
void SendSellOrder(string symbol, double entryPrice, double stopLossPoints, double takeProfitPoints, double orderDistancePoints, int expiration)
{
	double currentPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
	if (currentPrice < entryPrice + orderDistancePoints * _Point)
	{
		return;
	}
	double stopLoss = NormalizeDouble(entryPrice + stopLossPoints * _Point, _Digits);
	double takeProfit = NormalizeDouble(entryPrice - takeProfitPoints * _Point, _Digits);
	PrintFormat("current stats tp=%.5f, sl=%.5f, currentPrice=%.5f ", takeProfitPoints, stopLossPoints, entryPrice);
	double lotSize = 0.01;
	if (riskPercentage > 0)
	{
		lotSize = lotSizeOptimization(symbol, stopLoss - entryPrice);
	}
	ENUM_TIMEFRAMES assetTimeframe = GetAssetTimeframe(symbol); // Function to get the asset's timeframe
	datetime expirationTime = iTime(symbol, assetTimeframe, 0) + expiration * PeriodSeconds(assetTimeframe);
	string tradeComments = tradeComment + " - Sell Order";
	if (takeProfit <= currentPrice && stopLoss >= currentPrice)
	{
		trade.SellStop(lotSize, entryPrice, symbol, stopLoss, takeProfit, ORDER_TIME_SPECIFIED, expirationTime, tradeComments);
	}
	else
	{
		PrintFormat("failed to place sell stop tp=%.5f, sl=%.5f, currentPrice=%.5f, tpPoints=%.5f, slPoints=%.5f ", takeProfit, stopLoss, entryPrice, takeProfitPoints, stopLossPoints);
	}
}

//+------------------------------------------------------------------+
//| Function to place a buy stop order                               |
//+------------------------------------------------------------------+
void SendBuyOrder(string symbol, double entryPrice, double stopLossPoints, double takeProfitPoints, double orderDistancePoints, int expiration)
{
	double currentPrice = SymbolInfoDouble(symbol, SYMBOL_ASK);
	if (currentPrice > entryPrice - orderDistancePoints * _Point)
	{
		return;
	}
	double stopLoss = NormalizeDouble(entryPrice - stopLossPoints * _Point, _Digits);
	double takeProfit = NormalizeDouble(entryPrice + takeProfitPoints * _Point, _Digits);
	PrintFormat("current stats tp=%.5f, sl=%.5f, currentPrice=%.5f ", takeProfitPoints, stopLossPoints, entryPrice);
	double lotSize = 0.01;
	if (riskPercentage > 0)
	{
		lotSize = lotSizeOptimization(symbol, entryPrice - stopLoss);
	}
	ENUM_TIMEFRAMES assetTimeframe = GetAssetTimeframe(symbol); // Function to get the asset's timeframe
	datetime expirationTime = iTime(symbol, assetTimeframe, 0) + expiration * PeriodSeconds(assetTimeframe);
	string tradeComments = tradeComment + " Buy Order";
	if (takeProfit >= currentPrice && stopLoss <= currentPrice)
	{
		trade.BuyStop(lotSize, entryPrice, symbol, stopLoss, takeProfit, ORDER_TIME_SPECIFIED, expirationTime, tradeComments);
	}
	else
	{
		PrintFormat("failed to place buy stop tp=%.5f, sl=%.5f, currentPrice=%.5f, tpPoints=%.5f, slPoints=%.5f ", takeProfit, stopLoss, entryPrice, takeProfitPoints, stopLossPoints);
	}
}

//+------------------------------------------------------------------+
//| Close trades on drawdown                                         |
//+------------------------------------------------------------------+
void CloseTradesOnDrawdown()
{
	double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
	double drawdownLimit = accountBalance * DrawdownPercent / 100.0;
	for (int i = PositionsTotal() - 1; i >= 0; i--)
	{
		if (!positionInfo.SelectByIndex(i))
			continue;
		double positionLoss = positionInfo.Profit();
		ulong ticket = positionInfo.Ticket();
		positionLoss += positionInfo.Commission() + positionInfo.Swap();
		if (positionLoss < 0 && MathAbs(positionLoss) >= drawdownLimit && positionInfo.Magic() == MagicNumber)
		{
			if (trade.PositionClose(ticket))
				Print("Closed position due to drawdown: ", ticket);
			else
			{
				int error = GetLastError();
				Print("Failed to close position: ", ticket, ", Error: ", error);
				ResetLastError();
			}
		}
	}
}

// Function to get the asset's timeframe from assetConfigs
ENUM_TIMEFRAMES GetAssetTimeframe(string symbol)
{
	for (int i = 0; i < ArraySize(assetConfigs); i++)
	{
		if (assetConfigs[i].symbol == symbol)
		{
			return assetConfigs[i].timeframe;
		}
	}
	return PERIOD_CURRENT; // Default to current period if not found
}

// Function to check if we're in a live environment
bool IsLiveEnvironment()
{
	return AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_REAL;
}

// Function to send log data to the Node.js API
void LogToMongoDB(string jsonData)
{
	// Only proceed if we're in a live environment
	if (!IsLiveEnvironment())
		return;

	char result[];
	string headers = "Content-Type: application/json\r\n";
	char post[];
	StringToCharArray(jsonData, post, 0, StringLen(jsonData));

	int timeout = 5000;								   // 5 seconds timeout
	string url = "http://your-api-server-address/log"; // Replace with your actual API endpoint

	// Send HTTP POST request
	int res = WebRequest("POST", url, headers, timeout, post, result, headers);

	if (res != 200)
	{
		Print("Failed to log data to MongoDB. HTTP Error: ", res, " Response: ", CharArrayToString(result));
	}
}

// Function to log trade closure details
void LogTradeClose(ulong ticket, string closeReason)
{
	// Only proceed if we're in a live environment
	if (!IsLiveEnvironment())
		return;

	if (!PositionSelectByTicket(ticket))
		return;

	// Get position details
	string symbol = PositionGetString(POSITION_SYMBOL);
	double volume = PositionGetDouble(POSITION_VOLUME);
	ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
	string orderType = (posType == POSITION_TYPE_BUY) ? "buy" : "sell";
	datetime orderTime = (datetime)PositionGetInteger(POSITION_TIME);
	double orderPrice = PositionGetDouble(POSITION_PRICE_OPEN);
	long orderMagic = PositionGetInteger(POSITION_MAGIC);

	// Get account details
	long login = AccountInfoInteger(ACCOUNT_LOGIN);
	string accountName = AccountInfoString(ACCOUNT_NAME);
	string accountEnv = "live"; // Since we're only logging live trades

	// Format the JSON data
	string jsonData = StringFormat(
		"{\"timestamp\":\"%s\","
		"\"symbol\":\"%s\","
		"\"volume\":%.2f,"
		"\"order_type\":\"%s\","
		"\"order_id\":\"%d\","
		"\"order_time\":\"%s\","
		"\"order_price\":%.5f,"
		"\"order_volume\":%.2f,"
		"\"order_magic\":%d,"
		"\"order_reason\":\"%s\","
		"\"account_id\":\"%d\","
		"\"account_name\":\"%s\","
		"\"account_env\":\"%s\","
		"\"additional_info\":{"
		"\"profit\":%.2f,"
		"\"close_price\":%.5f,"
		"\"commission\":%.2f,"
		"\"swap\":%.2f"
		"}}",
		TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
		symbol,
		volume,
		orderType,
		ticket,
		TimeToString(orderTime, TIME_DATE | TIME_SECONDS),
		orderPrice,
		volume,
		orderMagic,
		closeReason,
		login,
		accountName,
		accountEnv,
		PositionGetDouble(POSITION_PROFIT),
		PositionGetDouble(POSITION_PRICE_CURRENT),
		PositionGetDouble(POSITION_COMMISSION),
		PositionGetDouble(POSITION_SWAP));

	LogToMongoDB(jsonData);
}

// Example usage in OnTradeTransaction
void OnTradeTransaction(const MqlTradeTransaction &trans,
						const MqlTradeRequest &request,
						const MqlTradeResult &result)
{
	// Check if this is a position close event
	if (trans.type == TRADE_TRANSACTION_DEAL_ADD)
	{
		string closeReason = "manual";
		if (HistoryDealGetInteger(trans.deal, DEAL_ENTRY) == DEAL_ENTRY_OUT)
		{
			// check if the entry is greater than the exit price for buy and less than the entry for sell: consider the entries hit my stop loss that we have moved and we closed the position in profit we should have a another label/reason for it
			if (trans.position == POSITION_TYPE_BUY)
			{
				if (trans.deal > trans.position)
					closeReason = "takeProfit";
			}
			else if (trans.position == POSITION_TYPE_SELL)
			{
				if (trans.deal < trans.position)
					closeReason = "takeProfit";
			}
		}

		LogTradeClose(trans.position, closeReason);
	}
}

//+------------------------------------------------------------------+
