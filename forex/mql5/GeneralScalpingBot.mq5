//+------------------------------------------------------------------+
//|                                                  ScalpingBot.mq5 |
//|                            Copyright 2024, Open lab technologies |
//|                              https://www.openlabtechnologies.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Open lab technologies"
#property link      "https://www.openlabtechnologies.com"
#property version   "1.01"

#include <Trade\Trade.mqh>
#include <Trade\OrderInfo.mqh>

CTrade trade;               // Object for trade operations
CPositionInfo positionInfo; // Object for position information
COrderInfo orderInfo;       // Object for order information

//+------------------------------------------------------------------+
//| Enums for Start and End Hours                                    |
//+------------------------------------------------------------------+

enum StartHour
  {
   Inactive = 0, _0000, _0100, _0200, _0300, _0400, _0500,
   _0600, _0700, _0800, _0900, _1000, _1100, _1200, _1300,
   _1400, _1500, _1600, _1700, _1800, _1900, _2000, _2100,
   _2200, _2300
  };

enum EndHour
  {
   Inactive = 0, _0000, _0100, _0200, _0300, _0400, _0500,
   _0600, _0700, _0800, _0900, _1000, _1100, _1200, _1300,
   _1400, _1500, _1600, _1700, _1800, _1900, _2000, _2100,
   _2200, _2300
  };

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
input group "==== Trading Profile =====";

// Enum for trading profile types
enum TradingProfileType
  {
   Forex = 0,
   Bitcoin = 1,
   _Gold = 2,
   UsIndices = 3
  };

// Input for selecting trading profile
input TradingProfileType tradingProfile = Forex; // Selected trading profile
int tradingProfileChoice; // Variable to hold the chosen trading profile

input group "===== Risk Management ====";
input double riskPercentage = 2.0;            // Risk percentage for position sizing
input uint positionSlippage = 100;             // Slippage in points
input double DrawdownPercent  = 5.0;          // Drawdown percentage threshold
input bool   useDrawdownPercent = false;      // Enable drawdown percent

input group "===== Order Management ====";
input int MagicNumber = 13;                    // Magic number for identifying trades
input string tradeComment = "";    // Comment for trades
input int expirationBars = 100;                 // Expiration time for pending orders
input int orderDistancePointsInp = 50;             // Distance from entry price for pending order placement

input group "===== Analysis Parameters ====";
input ENUM_TIMEFRAMES timeframe = PERIOD_CURRENT; // Timeframe for analysis
input int numberOfCandlesRange = 200;          // Number of candles range to search for highs/lows
input int barsToLookBack = 5;                  // Number of bars to look back for swing

input group "===== Trading Hours ====";
input StartHour startHour = 0;          // Start hour for trading
input EndHour endHour = 0;              // End hour for trading

//+------------------------------------------------------------------+
//| Trading Parameters for Different Markets                          |
//+------------------------------------------------------------------+
input group "==== Crypto Trading Parameters (Bitcoin) ====";
input double cryptoTakeProfitPercentage = 0.2;           // Take profit percentage for Bitcoin
input double cryptoStopLossPercentage = 0.2;             // Stop loss percentage for Bitcoin
input double cryptoTrailingStopLossAsPercentOfTP = 5;     // Trailing stop loss as percent of take profit for Bitcoin
input double cryptoTrailingStopLossTriggerAsPercentOfTP = 7; // Trigger for trailing stop loss as percent of take profit for Bitcoin

input group "==== Gold Trading Parameters ====";
input double goldTakeProfitPercentage = 0.2;             // Take profit percentage for Gold
input double goldStopLossPercentage = 0.2;               // Stop loss percentage for Gold
input double goldTrailingStopLossAsPercentOfTP = 5;       // Trailing stop loss as percent of take profit for Gold
input double goldTrailingStopLossTriggerAsPercentOfTP = 7; // Trigger for trailing stop loss as percent of take profit for Gold

input group "==== US Indices Trading Parameters ====";
input double indicesTakeProfitPercentage = 0.2;          // Take profit percentage for US Indices
input double indicesStopLossPercentage = 0.2;            // Stop loss percentage for US Indices
input double indicesTrailingStopLossAsPercentOfTP = 5;    // Trailing stop loss as percent of take profit for US Indices
input double indicesTrailingStopLossTriggerAsPercentOfTP = 7; // Trigger for trailing stop loss as percent of take profit for US Indices


input group "==== Forex Trading Parameters ====";
input double forexTakeProfitPoints = 200;            // Take profit points for Forex
input double forexStopLossPoints = 200;              // Stop loss as points for Forex
input double forexTrailingStopLossPoints = 10;      // Trailing stop loss for Forex
input double forexTrailingStopLossTrigger = 15; // Trigger for trailing stop loss as points


double takeProfitPoints,orderDistancePoints, stopLossPoints, trailingStopLossPoints,trailingStopTriggerPoints;
//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+

int startHourChoice; // Chosen start hour
int endHourChoice;   // Chosen end hour
int    consecutiveLosses;
double maxDailyLoss;
double dailyLoss;
datetime lastDailyReset;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- create timer
   trade.LogLevel(LOG_LEVEL_ERRORS);                 // Set logging level
   trade.SetExpertMagicNumber(MagicNumber);          // Set the magic number for trades
   ChartSetInteger(0, CHART_SHOW_GRID, false);       // Hide grid lines
   startHourChoice = startHour;                       // Retrieve start hour from input
   endHourChoice = endHour;                           // Retrieve end hour from input
   double askPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   switch(tradingProfile)
     {
      case Forex:
         tradingProfileChoice = Forex;
         break;
      case _Gold:
         tradingProfileChoice = _Gold;
         break;
      case Bitcoin:
         tradingProfileChoice = Bitcoin;
         break;
      case UsIndices:
         tradingProfileChoice = UsIndices;
         break;
     }
   return(INIT_SUCCEEDED);
  }



//+------------------------------------------------------------------+
//| Manage trailing stop loss                                         |
//+------------------------------------------------------------------+
void ManageTrailingStop()
  {
   double trailingStop = trailingStopLossPoints * _Point; // Calculate trailing stop in price
   double currentPrice = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits);
   double currentAsk = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK), _Digits);
// Iterate through all positions
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      // Select the position
      if(positionInfo.SelectByIndex(i))
        {
         ulong ticket = positionInfo.Ticket();
         double takeProfit = positionInfo.TakeProfit();
         double positionOpenPrice = positionInfo.PriceOpen();
         double currentStopLoss = positionInfo.StopLoss();
         // Only manage the buy positions for the current symbol
         if(positionInfo.Symbol() == _Symbol && positionInfo.PositionType() == POSITION_TYPE_BUY)
           {
            if(currentPrice - positionOpenPrice > (trailingStopTriggerPoints * _Point))
              {
               double newStopLoss = NormalizeDouble(currentPrice - trailingStop, _Digits);
               // Update stop loss only if it is higher than the current stop loss
               if(newStopLoss > currentStopLoss && newStopLoss !=0)
                 {
                  trade.PositionModify(ticket, newStopLoss, takeProfit);
                 }
              }
           }
         else
            if(positionInfo.Symbol() == _Symbol && positionInfo.PositionType() == POSITION_TYPE_SELL)
              {
               if(currentAsk + (trailingStopTriggerPoints * _Point) < positionOpenPrice)
                 {
                  double newStopLoss = NormalizeDouble(currentAsk + trailingStop, _Digits);
                  // Update stop loss only if it is lower than the current stop loss
                  if(newStopLoss < currentStopLoss &&  newStopLoss != 0)
                    {
                     trade.PositionModify(ticket, newStopLoss, takeProfit);
                    }
                 }
              }
        }
     }
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   ManageTrailingStop(); // Check and adjust trailing stop loss
   if(useDrawdownPercent)
     {
      CloseTradesOnDrawdown();
     }
   if(!isNewBar())
      return; // Only execute logic on new bars
   MqlDateTime time;
   TimeToStruct(TimeCurrent(), time); // Get current time
   int currentHour = time.hour; // Get current hour
   if(currentHour < startHourChoice)    // If before start hour, close all orders
     {
      CloseAllOrders();
      return;
     }
   if(currentHour >= endHourChoice && endHourChoice != 0)    // If after end hour, close all orders
     {
      CloseAllOrders();
      return;
     }
   int buyOrderTotal = 0; // Count of existing buy orders
   int sellOrderTotal = 0; // Count of existing sell orders
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      positionInfo.SelectByIndex(i);
      if(positionInfo.PositionType() == POSITION_TYPE_BUY && positionInfo.Symbol() == _Symbol && positionInfo.Magic() == MagicNumber)
        {
         buyOrderTotal++;
        }
      if(positionInfo.PositionType() == POSITION_TYPE_SELL && positionInfo.Symbol() == _Symbol && positionInfo.Magic() == MagicNumber)
        {
         sellOrderTotal++;
        }
     }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      orderInfo.SelectByIndex(i);
      if(orderInfo.OrderType() == ORDER_TYPE_BUY_STOP && orderInfo.Symbol() == _Symbol && orderInfo.Magic() == MagicNumber)
        {
         buyOrderTotal++;
        }
      if(orderInfo.OrderType() == ORDER_TYPE_SELL_STOP && orderInfo.Symbol() == _Symbol && orderInfo.Magic() == MagicNumber)
        {
         sellOrderTotal++;
        }
     }
   PrintFormat("The current value of buyOrderTotal= %.3f  and sellOrderTotal= %.3f ", buyOrderTotal, sellOrderTotal);
   PrintFormat("Total positions: %d, total orders: %d", PositionsTotal(), OrdersTotal());
   double askPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   switch(tradingProfile)
     {
      case Forex:
         takeProfitPoints = forexStopLossPoints;
         stopLossPoints = forexStopLossPoints;
         trailingStopLossPoints = forexTrailingStopLossPoints;
         trailingStopTriggerPoints = forexTrailingStopLossTrigger;
         orderDistancePoints = 100;
         break;
      case _Gold:
         takeProfitPoints = goldTakeProfitPercentage * askPrice; // conversion for Gold
         stopLossPoints = goldStopLossPercentage * askPrice;     // conversion for Gold
         trailingStopLossPoints= (goldTrailingStopLossAsPercentOfTP/100) * takeProfitPoints;
         trailingStopTriggerPoints = (goldTrailingStopLossTriggerAsPercentOfTP/100) * takeProfitPoints;
         orderDistancePoints = takeProfitPoints/2;
         break;
      case Bitcoin:
         takeProfitPoints = cryptoTakeProfitPercentage * askPrice; // conversion for Bitcoin
         stopLossPoints = cryptoStopLossPercentage * askPrice;     // conversion for Bitcoin
         trailingStopLossPoints = (cryptoTrailingStopLossAsPercentOfTP/100) * takeProfitPoints;
         trailingStopTriggerPoints = (cryptoTrailingStopLossTriggerAsPercentOfTP/100) * takeProfitPoints;
         orderDistancePoints = takeProfitPoints/2;
         break;
      case UsIndices:
         takeProfitPoints = indicesTakeProfitPercentage * askPrice; // conversion for US Indices
         stopLossPoints = indicesStopLossPercentage * askPrice;     // conversion for US Indices
         trailingStopLossPoints = (indicesTrailingStopLossAsPercentOfTP/100) * takeProfitPoints;
         trailingStopTriggerPoints = (indicesTrailingStopLossTriggerAsPercentOfTP/100) * takeProfitPoints;
         orderDistancePoints = takeProfitPoints/2;
         break;
     }
   if(buyOrderTotal <= 0)  // Place a buy order if no existing buy order
     {
      double entryPrice = findHighs();
      PrintFormat("Current buy price return %.5f", entryPrice);
      if(entryPrice > 0)
        {
         SendBuyOrder(entryPrice);
        }
     }
   if(sellOrderTotal <= 0)  // Place a sell order if no existing sell order
     {
      double entryPrice = findLows();
      PrintFormat("Current sell price return %.5f", entryPrice);
      if(entryPrice > 0)
        {
         SendSellOrder(entryPrice);
        }
     }
  }

//+------------------------------------------------------------------+
//| find the highest high within the last 'BarsN' bars               |
//+------------------------------------------------------------------+
double findHighs()
  {
   double highestHigh = 0;
   for(int i = 0; i < numberOfCandlesRange; i++)
     {
      double high = iHigh(_Symbol, timeframe, i);
      if(i > barsToLookBack && iHighest(_Symbol, timeframe, MODE_HIGH, barsToLookBack * 2 + 1, i - barsToLookBack) == i)
        {
         if(high > highestHigh)
            return high;
        }
      highestHigh = MathMax(high, highestHigh);
     }
   return  -1;
  }

//+------------------------------------------------------------------+
//| find the lowest low within the last 'barsToLookBack' bars        |
//+------------------------------------------------------------------+
double findLows()
  {
   double lowestLow = DBL_MAX;
   for(int i = 0; i < numberOfCandlesRange; i++)
     {
      double low = iLow(Symbol(), timeframe, i);
      if(i > barsToLookBack && iLowest(_Symbol, timeframe, MODE_LOW, barsToLookBack * 2 + 1, i - barsToLookBack) == i)
        {
         if(low < lowestLow)
            return low;
        }
      lowestLow = MathMin(low, lowestLow);
     }
   return -1;
  }

//+------------------------------------------------------------------+
//| Check if a new bar has formed                                    |
//+------------------------------------------------------------------+
bool isNewBar()
  {
   static datetime lastTime = 0;
   datetime currentTime = iTime(_Symbol, timeframe, 0);
   if(currentTime != lastTime)
     {
      lastTime = currentTime;
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Function to close all orders associated with the EA              |
//+------------------------------------------------------------------+
void CloseAllOrders()
  {
   for(int i = 0; i < OrdersTotal(); i++)
     {
      orderInfo.SelectByIndex(i);
      ulong ticket = orderInfo.Ticket();
      if(orderInfo.Symbol() == _Symbol && orderInfo.Magic() == MagicNumber)
        {
         trade.OrderDelete(ticket);
        }
     }
  }

//+------------------------------------------------------------------+
//| Function to calculate the optimal lot size based on risk         |
//+------------------------------------------------------------------+
double lotSizeOptimization(double stopLossPoints)
  {
   double risk = AccountInfoDouble(ACCOUNT_BALANCE) * riskPercentage / 100;
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minVolume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxVolume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double volumeLimit = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_LIMIT);
   double moneyPerLot = stopLossPoints / tickSize * tickValue * lotStep;
   double lots = MathFloor(risk / moneyPerLot) * lotStep;
   if(volumeLimit != 0)
      lots = MathMin(lots, volumeLimit);
   if(maxVolume != 0)
      lots = MathMin(lots, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX));
   if(minVolume != 0)
     {
      lots = MathMax(lots, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN));
     }
   lots = NormalizeDouble(lots, 2);
   return lots;
  }

//+------------------------------------------------------------------+
//| Function to place a sell stop order                              |
//+------------------------------------------------------------------+
void SendSellOrder(double entryPrice)
  {
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(currentPrice < entryPrice + orderDistancePoints * _Point)
     {
      return;
     }
   double stopLoss = NormalizeDouble(entryPrice + stopLossPoints * _Point, _Digits);
   double takeProfit = NormalizeDouble(entryPrice - takeProfitPoints * _Point, _Digits);
   PrintFormat("current stats tp=%.5f, sl=%.5f, currentPrice=%.5f ",takeProfitPoints,stopLossPoints, entryPrice);
   double lotSize = 0.01;
   if(riskPercentage > 0)
     {
      lotSize = lotSizeOptimization(stopLoss - entryPrice);
     }
   else
     {
      Print("The risk percent is 0 for this");
     }
   datetime expiration = iTime(_Symbol, timeframe, 0) + expirationBars * PeriodSeconds(timeframe);
   string tradeComments = tradeComment + " - Sell Order";
   if(takeProfit <= currentPrice && stopLoss >= currentPrice)
     {
      trade.SellStop(lotSize, entryPrice, _Symbol, stopLoss, takeProfit, ORDER_TIME_SPECIFIED, expiration, tradeComments);
     }
   else
     {
      PrintFormat("failed to place sell stop tp=%.5f, sl=%.5f, currentPrice=%.5f, tpPoints=%.5f, slPoints=%.5f ",takeProfit,stopLoss, entryPrice, takeProfitPoints, stopLossPoints);
     }
  }

//+------------------------------------------------------------------+
//| Function to place a buy stop order                               |
//+------------------------------------------------------------------+
void SendBuyOrder(double entryPrice)
  {
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(currentPrice > entryPrice - orderDistancePoints * _Point)
     {
      return;
     }
   double stopLoss = NormalizeDouble(entryPrice - stopLossPoints * _Point, _Digits);
   double takeProfit = NormalizeDouble(entryPrice + takeProfitPoints * _Point, _Digits);
   PrintFormat("current stats tp=%.5f, sl=%.5f, currentPrice=%.5f ",takeProfitPoints,stopLossPoints, entryPrice);
   double lotSize = 0.01;
   if(riskPercentage > 0)
     {
      lotSize = lotSizeOptimization(entryPrice - stopLoss);
     }
   datetime expiration = iTime(_Symbol, timeframe, 0) + expirationBars * PeriodSeconds(timeframe);
   string tradeComments = tradeComment + " Buy Order";
   if(takeProfit >= currentPrice && stopLoss <= currentPrice)
     {
      trade.BuyStop(lotSize, entryPrice, _Symbol, stopLoss, takeProfit, ORDER_TIME_SPECIFIED, expiration, tradeComment);
     }
   else
     {
      PrintFormat("failed to place buy stop tp=%.5f, sl=%.5f, currentPrice=%.5f, tpPoints=%.5f, slPoints=%.5f ",takeProfit,stopLoss, entryPrice, takeProfitPoints, stopLossPoints);
     }
  }

//+------------------------------------------------------------------+
//| Close trades on drawdown                                         |
//+------------------------------------------------------------------+
void CloseTradesOnDrawdown()
  {
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double drawdownLimit  = accountBalance * DrawdownPercent / 100.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!positionInfo.SelectByIndex(i))
         continue;
      double positionLoss = positionInfo.Profit();
      ulong  ticket       = positionInfo.Ticket();
      // Include commissions and swaps if needed
      positionLoss += positionInfo.Commission() + positionInfo.Swap();
      if(positionLoss < 0 && MathAbs(positionLoss) >= drawdownLimit && positionInfo.Magic() == MagicNumber)
        {
         if(trade.PositionClose(ticket))
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
//+------------------------------------------------------------------+
