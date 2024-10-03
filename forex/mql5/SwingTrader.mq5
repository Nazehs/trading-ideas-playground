//+------------------------------------------------------------------+
//|                                                       SwingTrader |
//|                        Copyright 2024, Open Lab Technologies. |
//|                                       https://www.openlabtechnologies.com |
//+------------------------------------------------------------------+
#property strict
#property copyright "Copyright 2024, Open Lab Technologies."
#property link      "https://www.openlabtechnologies.com"
#property version   "1.00"

#include <Trade\Trade.mqh>
#include <Trade\OrderInfo.mqh>
#include <Trade\PositionInfo.mqh>
#include <Indicators\Indicators.mqh> 

// Global objects for trade, position, and order operations.
CTrade trade;
CPositionInfo positionInfo;
COrderInfo orderInfo;

// Inputs
input int zigzagDepth = 12;            // Zigzag depth
input double takeProfitPoints = 50;           // Take profit in points
input double stopLossPoints = 50;             // Stop loss in points
input double lotSize = 0.1;             // Lot size

// Global variables
CIndicator zigzag;
int zigzagHandle = 0;

//--- initialization function
int OnInit()
{
   trade.LogLevel(LOG_LEVEL_ERRORS);
   trade.SetExpertMagicNumber(12345); // Set your magic number

   // Initialize Zigzag indicator
   zigzagHandle = zigzag.Init(Symbol(), PERIOD_CURRENT, MODE_HIGH, zigzagDepth);
   if (zigzagHandle == INVALID_HANDLE) {
      Print("Error initializing Zigzag indicator");
      return(INIT_FAILED);
   }

   return(INIT_SUCCEEDED);
}

//--- deinitialization function
void OnDeinit(const int reason)
{
   // Deinitialize Zigzag indicator
   if (zigzagHandle != INVALID_HANDLE) {
      zigzag.Deinit(zigzagHandle);
   }
}

//--- tick function
void OnTick()
{
   if (CheckDoubleTopBottom())
   {
      if (CheckIchimokuTrend() && IsBuySignal())
         OpenBuy();
      else if (!CheckIchimokuTrend() && IsSellSignal())
         OpenSell();
   }
}

//+------------------------------------------------------------------+
//| Function to check for double tops/bottoms using Zigzag        |
//+------------------------------------------------------------------+
bool CheckDoubleTopBottom()
{
   int lastZigzagIndex = zigzag.GetInteger(zigzagHandle, MODE_HIGH, 0);

   if (lastZigzagIndex < 0)
      return false;

   double lastHigh = zigzag.GetDouble(zigzagHandle, MODE_HIGH, lastZigzagIndex);
   double lastLow = zigzag.GetDouble(zigzagHandle, MODE_LOW, lastZigzagIndex + 1);

   // Check for double top/bottom conditions
   if (iHigh(Symbol(), PERIOD_CURRENT, lastZigzagIndex) == lastHigh && iLow(Symbol(), PERIOD_CURRENT, lastZigzagIndex + 1) == lastLow)
      return true; // Found a double top/bottom

   return false;
}

//+------------------------------------------------------------------+
//| Function to check Ichimoku trend                                |
//+------------------------------------------------------------------+
bool CheckIchimokuTrend()
{
   double senkouSpanA = iIchimoku(Symbol(), PERIOD_CURRENT, 9, 26, 52, SENKOUSPANA_LINE, 0);
   double senkouSpanB = iIchimoku(Symbol(), PERIOD_CURRENT, 9, 26, 52, SENKOUSPANB_LINE, 0);
   double closePrice = iClose(Symbol(), PERIOD_CURRENT, 0);

   // Check if price is above the cloud for buy and below for sell
   return (closePrice > senkouSpanA && closePrice > senkouSpanB); // Bullish trend
}

//+------------------------------------------------------------------+
//| Function to open buy order                                       |
//+------------------------------------------------------------------+
void OpenBuy()
{
   double askPrice = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK), _Digits);
   double sl = NormalizeDouble(askPrice - stopLossPoints * _Point, _Digits);
   double tp = NormalizeDouble(askPrice + takeProfitPoints * _Point, _Digits);

   // Send buy order
   int ticket = trade.Buy(lotSize, _Symbol, askPrice, sl, tp, "Buy Order");

   if (ticket < 0) {
      Print("Error opening buy order: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Function to open sell order                                      |
//+------------------------------------------------------------------+
void OpenSell()
{
   double bidPrice = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits);
   double sl = NormalizeDouble(bidPrice + stopLossPoints * _Point, _Digits);
   double tp = NormalizeDouble(bidPrice - takeProfitPoints * _Point, _Digits);

   // Send sell order
   int ticket = trade.Sell(lotSize, _Symbol, bidPrice, sl, tp, "Sell Order");

   if (ticket < 0) {
      Print("Error opening sell order: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Function to check if signal is buy                               |
//+------------------------------------------------------------------+
bool IsBuySignal()
{
   double lastZigzagHigh = zigzag.GetDouble(zigzagHandle, MODE_HIGH, 0);
   double currentPrice = iClose(Symbol(), PERIOD_CURRENT, 0);

   // Buy if the current price is above the last Zigzag high
   return (currentPrice > lastZigzagHigh);
}

//+------------------------------------------------------------------+
//| Function to check if signal is sell                              |
//+------------------------------------------------------------------+
bool IsSellSignal()
{
   double lastZigzagLow = zigzag.GetDouble(zigzagHandle, MODE_LOW, 1);
   double currentPrice = iClose(Symbol(), PERIOD_CURRENT, 0);

   // Sell if the current price is below the last Zigzag low
   return (currentPrice < lastZigzagLow);
}
//+------------------------------------------------------------------+