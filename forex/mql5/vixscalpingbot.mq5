//+------------------------------------------------------------------+
//|                                                  ScalpingBot.mq5 |
//|                            Copyright 2024, Open lab technologies |
//|                              https://www.openlabtechnologies.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Open lab technologies"
#property link      "https://www.openlabtechnologies.com"
#property version   "1.02"
#include <Trade\Trade.mqh>
#include <Trade\OrderInfo.mqh>
const string VERSION = "1.02";

CTrade trade;               // Object for trade operations
CPositionInfo positionInfo; // Object for position information
COrderInfo orderInfo;       // Object for order information

//+------------------------------------------------------------------+
//| Enums for Start and End Hours                                    |
//+------------------------------------------------------------------+
enum StartHour
  {
   Inactive=0, _0000, _0100, _0200, _0300, _0400, _0500,
   _0600, _0700, _0800, _0900, _1000, _1100, _1200, _1300,
   _1400, _1500, _1600, _1700, _1800, _1900, _2000, _2100,
   _2200, _2300
  };

enum EndHour
  {
   Inactive=0, _0000, _0100, _0200, _0300, _0400, _0500,
   _0600, _0700, _0800, _0900, _1000, _1100, _1200, _1300,
   _1400, _1500, _1600, _1700, _1800, _1900, _2000, _2100,
   _2200, _2300
  };
enum LotSizingMethod {FIXED, RISK_BASED};
//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
input group "===== Risk Management ====";
input double riskPercentage = 2;                 // Risk percentage for position sizing
input int stopLossPoints = 250;                   // Stop loss in points
input int takeProfitPoints = 300;                 // Take profit in points
input int trailingStopLossPoints = 10;            // Trailing stop loss in points
input int trailingStopTriggerPoints = 50;         // Trigger for activating trailing stop loss
input uint positionSlippage = 100;                // Slippage in points
input  LotSizingMethod lotSizingMethod = RISK_BASED; // Lot sizing method
input double fixedLotSize = 0.01;                // Fixed lot size to use if FIXED method is selected
input double DrawdownPercent  = 5.0;          // Drawdown percentage threshold


input group "===== Trade Settings ====";
input int MagicNumber = 13;                        // Magic number for identifying trades
input string tradeComment = "Scalper Nigs";       // Comment for trades
input int expirationBars = 100;                    // Expiration time for pending orders
input int orderDistancePoints = 50;                // Distance from entry price for pending order placement


input group "===== Analysis Parameters ====";
input ENUM_TIMEFRAMES timeframe = PERIOD_CURRENT; // Timeframe for analysis
input int numberOfCandlesRange = 200;             // Number of candles range to search for highs/lows based on barsToLookBack
input int barsToLookBack = 5;                     // Number of bars to look back for swing

input group "===== Trading Hours ====";
input StartHour startHour = 0;             // Start hour for trading
input EndHour endHour = 0;                 // End hour for trading

input group "===== Dynamic Stop Loss and Take Profit ====";
input int atrPeriod = 14;             // Period for ATR calculation
input double atrMultiplierSL = 2.0;    // Multiplier for ATR-based stop loss
input double atrMultiplierTP = 3.0;    // Multiplier for ATR-based take profit
input double swingTPBufferMultiplier = 0.5; // Multiplier for TP buffer based on swing distance
input uint SLCandlesLookBack = 50;           // number of candles to look back for previous

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
int startHourChoice; // Chosen start hour
int endHourChoice;   // Chosen end hour
string appName ="vixScalpingBot-" +VERSION ;

int handle_atr; // Handle for the ATR indicator
double atrBuffer[]; // Buffer to store ATR values
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.LogLevel(LOG_LEVEL_ERRORS);                // logging level
   trade.SetDeviationInPoints(positionSlippage);
   trade.SetExpertMagicNumber(MagicNumber); // Set the magic number for trades
   ChartSetInteger(0, CHART_SHOW_GRID, false); // Hide grid lines
   handle_atr = iATR(_Symbol, timeframe, atrPeriod);
   if(handle_atr == -1)
     {
      Print("Error creating ATR handle: ", GetLastError());
      return(INIT_FAILED);
     }

   ArraySetAsSeries(atrBuffer, true);
   return(INIT_SUCCEEDED);
  }


//+------------------------------------------------------------------+
//|                                                                  |
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
//|                                                                  |
//+------------------------------------------------------------------+
void OnTick()
  {
   ManageTrailingStop();
//ManageOpenPositions(); // manage positions and pending orders
//CancelPendingOrders(); // to cancel pending orders
   CloseTradesOnDrawdown();

   if(!isNewBar())
      return;

   MqlDateTime time;
   TimeToStruct(TimeCurrent(), time); // Get current time
   startHourChoice = startHour; // Retrieve start hour from input
   endHourChoice = endHour; // Retrieve end hour from input
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

   if(buyOrderTotal <= 0)  // Place a buy order if no existing buy order
     {
      double entryPrice = findHighs();
      if(entryPrice > 0)
        {
         SendBuyOrder(entryPrice);
        }
     }

   if(sellOrderTotal <= 0)  // Place a sell order if no existing sell order
     {
      double entryPrice = findLows();
      if(entryPrice > 0)
        {
         SendSellOrder(entryPrice);
        }
     }
  }


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double findPreviousSwingLow(double currentPrice)
  {
   double lowestLow = DBL_MAX;
   int lowestLowIndex = -1;

   for(int i = 1; i < numberOfCandlesRange; ++i)  // Start from 1 to look back
     {
      double low = iLow(_Symbol, timeframe, i);
      if(low < currentPrice && low < lowestLow)
        {
         if(i > SLCandlesLookBack && iLowest(_Symbol, timeframe, MODE_LOW, SLCandlesLookBack * 2 + 1, i - SLCandlesLookBack) == i)
           {
            lowestLow = low;
            lowestLowIndex = i;
           }
        }
      if(lowestLowIndex != -1)
         return lowestLow; // Returning the first swing low is found below the current price
     }



   return 0; // Return 0 if no previous swing low found
  }


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double findPreviousSwingHigh(double currentPrice)
  {
   double highestHigh = 0;
   int highestHighIndex = -1;

   for(int i = 1; i < numberOfCandlesRange; ++i)  // Start from 1 to look back
     {
      double high = iHigh(_Symbol, timeframe, i);
      if(high > currentPrice && high > highestHigh)
        {
         if(i > SLCandlesLookBack && iHighest(_Symbol, timeframe, MODE_HIGH, SLCandlesLookBack * 2 + 1, i - SLCandlesLookBack) == i)
           {
            highestHigh = high;
            highestHighIndex = i;
           }
        }
      if(highestHighIndex != -1)
         return highestHigh; //Returning the first swing high is found above the current price
     }


   return 0; // Return 0 if no previous swing high found
  }
//+------------------------------------------------------------------+
//|                                                                  |
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
//|                                                                  |
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
//|                                                                  |
//+------------------------------------------------------------------+
bool isNewBar()
  {
   static datetime lastTime = 0;
   datetime currentTime = iTime(_Symbol, timeframe, 0);
   if(currentTime != lastTime)
     {
      lastTime = currentTime;
      if(CopyBuffer(handle_atr, 0, 0, 1, atrBuffer) <= 0)   //Copy current atr value
        {
         Print("Error copying ATR buffer: ", GetLastError());
        }
      return true;
     }
   return false;
  }


//+------------------------------------------------------------------+
//|                                                                  |
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
//|                                                                  |
//+------------------------------------------------------------------+
double lotSizeOptimization(double stopLossPoints)
  {
   double riskpercent = riskPercentage;

// Input validation
   if(stopLossPoints <= 0)
     {
      Print("Warning: Invalid stop loss points");
      return 0.01; // Return minimum lot size
     }

   if(riskpercent <= 0 || riskpercent > 100)
     {
      Print("Warning: Invalid risk percentage, using 1%");
      riskpercent = 1.0;
     }
// if user wants to use a fix lot size
   if(lotSizingMethod == FIXED)
     {
      return fixedLotSize;
     }

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
//|                                                                  |
//+------------------------------------------------------------------+
void SendBuyOrder(double entryPrice)
  {
// Get current market price
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

// Check if current price meets entry criteria
   if(currentPrice > entryPrice - orderDistancePoints * _Point)
     {
      Print("Current price exceeds entry criteria. Order not placed.");
      return;
     }

// Get the latest ATR value
   double atr = (CopyBuffer(handle_atr, 0, 0, 1, atrBuffer) > 0) ? atrBuffer[0] : 0;
   if(atr == 0)
     {
      Print("Error getting ATR value in SendBuyOrder. Skipping order placement.");
      return;
     }

// Find the previous swing low
   double previousSwingLow = findPreviousSwingLow(entryPrice);
   double stopLoss, takeProfit;

// Determine stop loss and take profit based on previous swing low
   if(previousSwingLow != 0)
     {
      stopLoss = NormalizeDouble(previousSwingLow, _Digits); // Use previous swing low
      double swingLowDistance = entryPrice - previousSwingLow;
      double tpBuffer = swingLowDistance * swingTPBufferMultiplier;
      takeProfit = NormalizeDouble(entryPrice + MathMax(atr * atrMultiplierTP, tpBuffer), _Digits);
     }
   else
     {
      stopLoss = NormalizeDouble(entryPrice - atrMultiplierSL * atr, _Digits); // Default to ATR-based SL
      takeProfit = NormalizeDouble(entryPrice + atr * atrMultiplierTP, _Digits); // TP based on entry and ATR
     }

// Calculate lot size based on risk
   double lotSize = lotSizeOptimization(MathAbs(entryPrice - stopLoss));

// Set order expiration time
   datetime expiration = iTime(_Symbol, timeframe, 0) + expirationBars * PeriodSeconds(timeframe);
   string tradeComment = appName + " - BUY ORDER"  ;

// Log order details
   PrintFormat("Buy Order: Entry=%.5f, SL=%.5f, TP=%.5f, ATR=%.5f, LotSize=%.2f",
               entryPrice, stopLoss, takeProfit, atr, lotSize);

// Check conditions for placing the buy order
   if(takeProfit >= currentPrice && stopLoss <= currentPrice)
     {
      if(trade.BuyStop(lotSize, entryPrice, _Symbol, stopLoss, takeProfit, ORDER_TIME_SPECIFIED, expiration, tradeComment) == -1)
        {
         Print("Error Placing Buy Order: ", trade.ResultRetcodeDescription());
        }
      else
        {
         Print("Buy Stop Order Placed Successfully. Ticket #");
        }
     }
   else
     {
      Print("Buy Stop Order Not Placed - Price conditions not met.");
     }
  }


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void SendSellOrder(double entryPrice)
  {
// Get current market price
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

// Check if current price meets entry criteria
   if(currentPrice < entryPrice + orderDistancePoints * _Point)
     {
      Print("Current price does not meet entry criteria. Order not placed.");
      return;
     }

// Get the latest ATR value
   double atr = (CopyBuffer(handle_atr, 0, 0, 1, atrBuffer) > 0) ? atrBuffer[0] : 0;
   if(atr == 0)
     {
      Print("Error getting ATR value in SendSellOrder. Skipping order placement.");
      return;
     }

// Find the previous swing high
   double previousSwingHigh = findPreviousSwingHigh(entryPrice);
   double stopLoss, takeProfit;

// Determine stop loss and take profit based on previous swing high
   if(previousSwingHigh != 0)
     {
      stopLoss = NormalizeDouble(previousSwingHigh, _Digits); // Previous swing high as SL
      double swingHighDistance = previousSwingHigh - entryPrice;
      double tpBuffer = swingHighDistance * swingTPBufferMultiplier;
      takeProfit = NormalizeDouble(entryPrice - MathMax(atr * atrMultiplierTP, tpBuffer), _Digits); // TP: Max of ATR or swing distance + buffer
     }
   else
     {
      Print("No previous swing high found for Sell order. Defaulting to ATR-based SL.");
      stopLoss = NormalizeDouble(entryPrice + atrMultiplierSL * atr, _Digits); // Default to ATR-based SL
      takeProfit = NormalizeDouble(entryPrice - atr * atrMultiplierTP, _Digits); // TP based on entry and ATR
     }

// Calculate lot size based on risk
   double lotSize = lotSizeOptimization(MathAbs(stopLoss - entryPrice));

// Set order expiration time
   datetime expiration = iTime(_Symbol, timeframe, 0) + expirationBars * PeriodSeconds(timeframe);
   string tradeComment = appName + " - Sell Order";

// Log order details
   PrintFormat("Sell Order: Entry=%.5f, SL=%.5f, TP=%.5f, ATR=%.5f, LotSize=%.2f",
               entryPrice, stopLoss, takeProfit, atr, lotSize);

// Check conditions for placing the sell order
   if(takeProfit <= currentPrice && stopLoss >= currentPrice)    // Check order validity
     {
      if(trade.SellStop(lotSize, entryPrice, _Symbol, stopLoss, takeProfit, ORDER_TIME_SPECIFIED, expiration, tradeComment) == -1)
        {
         Print("Error Placing Sell Order: ", trade.ResultRetcodeDescription());
        }
      else
        {
         Print("Sell Stop Order Placed Successfully. Ticket #");
        }
     }
   else
     {
      Print("Sell Stop Order Not Placed - Price conditions not met.");
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
