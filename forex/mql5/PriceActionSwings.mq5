//+------------------------------------------------------------------+
//|                                                     PriceActionSwings.mq5 |
//|                        Nazeh Abel                                  |
//|                        https://www.openlabtechnologies.com                   |
//+------------------------------------------------------------------+
#property strict
#include <Trade\Trade.mqh>
#include <Trade\OrderInfo.mqh>

// Global objects for trade, position, and order operations.
CTrade trade;
CPositionInfo positionInfo;
COrderInfo orderInfo;

// Order counts
int buyOrderCount = 0;
int sellOrderCount = 0;



// Variables to track swing points
int lastSwingHighIndex = -1;
int lastSwingLowIndex = -1;

// Trading Parameters
input double lotSize = 0.02;            // Lot size for the order.
input double trailingStopLossPoints = 20; // Trailing stop in points.
input double stopLossPoints = 100;      // Initial stop loss in points.
input double takeProfitPoints = 200;   // Take profit in points.
input double entryPriceThreshold = 0.0001; // Minimum price change to enter a trade.
input ENUM_TIMEFRAMES timeframe = PERIOD_CURRENT; // Timeframe for analysis.
input int magicNumber = 00013; // Magic number for identifying trades.
input int trailingStopTriggerPoints = 10; // Trigger for activating trailing stop loss.
// Input Parameters
input int lookbackWindow = 10; // Number of bars to look back for swing analysis.
input int shoulder = 5;       // Number of bars on each side for peak finding.
input int markerSize = 10;  // Size of the marker (in pixels).
// Global variables for trade management
double initialStopLoss;
double takeProfit;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
// Set logging level and magic number for trades.
   trade.LogLevel(LOG_LEVEL_ERRORS);
   trade.SetExpertMagicNumber(magicNumber);

// Hide grid lines for visual clarity.
   ChartSetInteger(0, CHART_SHOW_GRID, false);

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
// Cleanup code can be added here if needed.
  }

//+------------------------------------------------------------------+
//| Check for new bar                                                |
//+------------------------------------------------------------------+
bool isNewBar()
  {
   static datetime lastTime = 0;
   datetime currentTime = iTime(_Symbol, PERIOD_CURRENT, 0);

// Check if the current time is different from the last recorded time.
   if(currentTime != lastTime)
     {
      lastTime = currentTime;
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
// Manage trailing stop loss for open positions.
   ManageTrailingStop();

// Get the current bar index.
   int currentBar = iBarShift(Symbol(), PERIOD_CURRENT, 0);

// Find peak points and draw trend lines.
   int bar1 = FindPeak(MODE_HIGH, lookbackWindow, 0);
   if(bar1 != -1)
     {
      int bar2 = FindPeak(MODE_HIGH, lookbackWindow, bar1 + 1);

      // Draw the upper trend line.
      ObjectDelete(0, "upper");
      if(ObjectCreate(0, "upper", OBJ_TREND, 0,
                      iTime(Symbol(), Period(), bar2), iHigh(Symbol(), Period(), bar2),
                      iTime(Symbol(), Period(), bar1), iHigh(Symbol(), Period(), bar1)))
        {
         ObjectSetInteger(0, "upper", OBJPROP_COLOR, clrBlue);
         ObjectSetInteger(0, "upper", OBJPROP_WIDTH, 2);
         ObjectSetInteger(0, "upper", OBJPROP_RAY_RIGHT, true);
        }
      else
        {
         Print("Error creating upper trend line: ", GetLastError());
        }
     }

   bar1 = FindPeak(MODE_LOW, lookbackWindow, 0);
   if(bar1 != -1)
     {
      int bar2 = FindPeak(MODE_LOW, lookbackWindow, bar1 + 1);

      // Draw the lower trend line.
      ObjectDelete(0, "lower");
      if(ObjectCreate(0, "lower", OBJ_TREND, 0,
                      iTime(Symbol(), Period(), bar2), iLow(Symbol(), Period(), bar2),
                      iTime(Symbol(), Period(), bar1), iLow(Symbol(), Period(), bar1)))
        {
         ObjectSetInteger(0, "lower", OBJPROP_COLOR, clrRed);
         ObjectSetInteger(0, "lower", OBJPROP_WIDTH, 2);
         ObjectSetInteger(0, "lower", OBJPROP_RAY_RIGHT, true);
        }
      else
        {
         Print("Error creating lower trend line: ", GetLastError());
        }
     }

// Find swing high and low prices.
   double swingHighPrice = FindSwingHigh(lookbackWindow, PERIOD_CURRENT);
   double swingLowPrice = FindSwingLow(lookbackWindow, PERIOD_CURRENT);

// Update the last swing high and low indices.
   lastSwingHighIndex = FindPeak(MODE_HIGH, lookbackWindow, 0);
   lastSwingLowIndex = FindPeak(MODE_LOW, lookbackWindow, 0);

// Flags to prevent repeated orders.
   bool buyOrderPlaced = false;
   bool sellOrderPlaced = false;

// Mark swing highs.
   if(iLow(NULL, PERIOD_CURRENT, 0) == swingLowPrice)
     {
      // ObjectDelete(0, "buyArrow"); // Delete previous marker if exists
      // CreateBuyArrow("buyArrow", swingLowPrice, 10);
      buyOrderPlaced = false;
     }

// Mark swing lows.
   if(iHigh(NULL, PERIOD_CURRENT, 0) == swingHighPrice)
     {
      // ObjectDelete(0, "sellArrow"); // Delete previous marker if exists
      // CreateSellArrow("sellArrow", swingHighPrice, 10);
      sellOrderPlaced = false;
     }

// Place orders based on swing detection and bar confirmation.
   if(isNewBar() && !buyOrderPlaced && buyOrderCount <= 0)
     {
      // Place Buy Order if a swing low is detected on the higher timeframe.
      if(FindLowestBarIndex(timeframe, lookbackWindow) == 1)
        {
         PlaceBuyOrder();
         buyOrderPlaced = true; // Set flag to true after placing order
        }
     }

   if(!sellOrderPlaced && sellOrderCount <= 0)
     {
      // Place Sell Order if a swing high is detected on the higher timeframe.
      if(FindHighestBarIndex(timeframe, lookbackWindow) == 1)
        {

         PlaceSellOrder();
         sellOrderPlaced = true; // Set flag to true after placing order
        }
     }
// Update order and position counts.
   openOrderAndPositions();
  }

//+------------------------------------------------------------------+
//| Find the index of the highest bar                              |
//+------------------------------------------------------------------+
int FindHighestBarIndex(ENUM_TIMEFRAMES timeframe, int count, int startBar = 0)
  {
   return iHighest(NULL, timeframe, MODE_HIGH, count, startBar);
  }

//+------------------------------------------------------------------+
//| Find the index of the lowest bar                               |
//+------------------------------------------------------------------+
int FindLowestBarIndex(ENUM_TIMEFRAMES timeframe, int count, int startBar = 0)
  {
   return iLowest(NULL, timeframe, MODE_LOW, count, startBar);
  }

//+------------------------------------------------------------------+
//| Find a swing high                                               |
//+------------------------------------------------------------------+
double FindSwingHigh(int lookbackWindow, ENUM_TIMEFRAMES timeframe)
  {
   int highestBarIndex = FindHighestBarIndex(timeframe, lookbackWindow);
   return iHigh(NULL, timeframe, highestBarIndex);
  }

//+------------------------------------------------------------------+
//| Find a swing low                                                |
//+------------------------------------------------------------------+
double FindSwingLow(int lookbackWindow, ENUM_TIMEFRAMES timeframe)
  {
   int lowestBarIndex = FindLowestBarIndex(timeframe, lookbackWindow);
   return iLow(NULL, timeframe, lowestBarIndex);
  }

//+------------------------------------------------------------------+
//| Enhanced FindNextPeak function to find peaks                    |
//+------------------------------------------------------------------+
int FindNextPeak(int mode, int count, int startBar)
  {
   if(startBar < 0)
     {
      count += startBar;
      startBar = 0;
     }
   return (mode == MODE_HIGH) ? iHighest(Symbol(), Period(), (ENUM_SERIESMODE)mode, count, startBar) : iLowest(Symbol(), Period(), (ENUM_SERIESMODE)mode, count, startBar);
  }

//+------------------------------------------------------------------+
//| Main peak finding function.                                     |
//+------------------------------------------------------------------+
int FindPeak(int mode, int count, int startBar)
  {
// Validate the mode input parameter.
   if(mode != MODE_HIGH && mode != MODE_LOW)
      return -1;

   int currentBar = startBar;
   int foundPeak = FindNextPeak(mode, count * 2 + 1, currentBar - count);

// Loop through the bars to identify the peak.
   while(foundPeak != currentBar)
     {
      currentBar = FindNextPeak(mode, count, currentBar + 1);
      foundPeak = FindNextPeak(mode, count * 2 + 1, currentBar - count);
     }
   return currentBar;
  }

//+------------------------------------------------------------------+
//| Place buy order position                                         |
//+------------------------------------------------------------------+
void PlaceBuyOrder()
  {
// Get current bid price and last close price.
   double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double lastPrice = iClose(_Symbol, 0, 1);

// Calculate initial stop loss and take profit levels.
   initialStopLoss = currentBid - (stopLossPoints * _Point);
   takeProfit = currentBid + (takeProfitPoints * _Point);

// Open a buy order if conditions are met.
   if(trade.Buy(lotSize, _Symbol, currentBid, initialStopLoss, takeProfit))
     {
      Print("Buy order opened at: ", currentBid);
     }
   else
     {
      Print("Error opening buy order: ", GetLastError());
     }
  }

//+------------------------------------------------------------------+
//| Place sell order position                                        |
//+------------------------------------------------------------------+
void PlaceSellOrder()
  {
// Get current ask price and last close price.
   double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double lastPrice = iClose(_Symbol, 0, 1);

// Calculate initial stop loss and take profit levels.
   initialStopLoss = currentAsk + (stopLossPoints * _Point);
   takeProfit = currentAsk - (takeProfitPoints * _Point);

// Open a sell order if conditions are met.
   if(trade.Sell(lotSize, _Symbol, currentAsk, initialStopLoss, takeProfit))
     {
      Print("Sell order opened at: ", currentAsk);
     }
   else
     {
      Print("Error opening sell order: ", GetLastError());
     }
  }

//+------------------------------------------------------------------+
//| Place a buy order                                              |
//+------------------------------------------------------------------+
void PlaceBuyOrder(double volume, double stopLoss, double takeProfit)
  {
// Get current ask price and calculate normalized stop loss and take profit levels.
   double askPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl = NormalizeDouble(askPrice - stopLoss *_Point, _Digits);
   double tp = NormalizeDouble(askPrice + takeProfit * _Point, _Digits);

// Send the buy order.
   int ticket = trade.Buy(volume, _Symbol, askPrice, sl, tp, "Buy Order");

   if(ticket < 0)
     {
      Print("Error placing buy order: ", GetLastError());
      return;
     }

   Print("Buy order placed successfully: ", ticket);
  }

//+------------------------------------------------------------------+
//| Place a sell order                                             |
//+------------------------------------------------------------------+
void PlaceSellOrder(double volume, double stopLoss, double takeProfit)
  {
// Get current bid price and calculate normalized stop loss and take profit levels.
   double bidPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = NormalizeDouble(bidPrice + stopLoss * _Point, _Digits);
   double tp = NormalizeDouble(bidPrice - takeProfit * _Point, _Digits);

// Send the sell order.
   int ticket = trade.Sell(volume, _Symbol, bidPrice, sl, tp, "Sell Order");

   if(ticket < 0)
     {
      Print("Error placing sell order: ", GetLastError());
      return;
     }

   Print("Sell order placed successfully: ", ticket);
  }

//+------------------------------------------------------------------+
//| Count open orders and positions                                   |
//+------------------------------------------------------------------+
void openOrderAndPositions()
  {
// Reset order counters.
   buyOrderCount = 0;
   sellOrderCount = 0;

// Loop through open positions.
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      // Select the position and check if it's a buy or sell order for the current symbol.
      if(positionInfo.SelectByIndex(i))
        {
         if(positionInfo.PositionType() == POSITION_TYPE_BUY && positionInfo.Symbol() == _Symbol && positionInfo.Magic() == magicNumber)
           {
            buyOrderCount++;
           }
         if(positionInfo.PositionType() == POSITION_TYPE_SELL && positionInfo.Symbol() == _Symbol && positionInfo.Magic() == magicNumber)
           {
            sellOrderCount++;
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Manage trailing stop loss                                         |
//+------------------------------------------------------------------+
void ManageTrailingStop()
  {
// Calculate trailing stop in price.
   double trailingStop = trailingStopLossPoints * _Point;

// Get current bid and ask prices.
   double currentPrice = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits);
   double currentAsk = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK), _Digits);

// Loop through open positions.
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      // Select the position.
      if(positionInfo.SelectByIndex(i))
        {
         ulong ticket = positionInfo.Ticket();
         double takeProfit = positionInfo.TakeProfit();

         // Only manage the buy positions for the current symbol.
         if(positionInfo.Symbol() == _Symbol && positionInfo.PositionType() == POSITION_TYPE_BUY)
           {
            double orderOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double orderStopLoss = PositionGetDouble(POSITION_SL);

            // Check if trailing stop conditions are met.
            if(currentPrice - positionInfo.PriceOpen() > (trailingStopTriggerPoints * _Point))
              {
               // Calculate the new stop loss level.
               double newStopLoss = NormalizeDouble(currentPrice - trailingStop, _Digits);

               // Update stop loss if the new stop loss is higher than the current stop loss.
               if(newStopLoss > positionInfo.StopLoss() && newStopLoss != 0)
                 {
                  if(trade.PositionModify(ticket, newStopLoss, takeProfit))
                    {
                     Print("Trailing stop updated to: ", newStopLoss);
                    }
                  else
                    {
                     Print("Error modifying position: ", GetLastError());
                    }
                 }
              }
           }
         else
            if(positionInfo.Symbol() == _Symbol && positionInfo.PositionType() == POSITION_TYPE_SELL)
              {
               double orderOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
               double orderStopLoss = PositionGetDouble(POSITION_SL);

               // Check if trailing stop conditions are met for sell positions.
               if(currentAsk + (trailingStopTriggerPoints * _Point) < positionInfo.PriceOpen())
                 {
                  // Calculate the new stop loss level.
                  double newStopLoss = NormalizeDouble(currentAsk + trailingStop, _Digits);

                  // Update stop loss if the new stop loss is lower than the current stop loss.
                  if(newStopLoss < positionInfo.StopLoss() &&  newStopLoss != 0)
                    {
                     if(trade.PositionModify(ticket, newStopLoss, takeProfit))
                       {
                        Print("Sell trailing stop updated to: ", newStopLoss);
                       }
                     else
                       {
                        Print("Error modifying sell position: ", GetLastError());
                       }
                    }
                 }
              }
        }
     }
  }
//+------------------------------------------------------------------+
