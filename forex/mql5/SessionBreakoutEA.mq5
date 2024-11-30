//+------------------------------------------------------------------+
//|                                            SessionBreakoutEA.mq5 |
//+------------------------------------------------------------------+
#property copyright ""
#property link      ""
#property version   "1.10"
#property strict

#include <Trade\Trade.mqh>          // CTrade class
#include <Trade\PositionInfo.mqh>   // CPositionInfo class
#include <Trade\OrderInfo.mqh>      // COrderInfo class
#include <Arrays\ArrayObj.mqh>      // CArrayObj class

// Input parameters
input string Symbols            = "EURUSD,GBPUSD,AUDUSD,USDJPY,USDCAD,XAUUSD,USDCHF"; // List of symbols to trade
input double RiskRewardRatio    = 3.0;    // Risk-reward ratio
input double LotSize            = 0.1;    // Lot size
input bool   UseDefaultSessions = true;   // Use default trading sessions
input bool   UseCustomSessions  = false;  // Use custom trading sessions
input string CustomSessions     = "";     // Custom sessions in "Name,StartHour,StartMinute;..." format
// Magic number for the EA
input uint MAGIC_NUMBER = 123456;

// Class to hold session information
class SessionTime : public CObject
{
public:
   string   Name;
   int      StartHour;
   int      StartMinute;
   datetime LastProcessedDate;

   // Constructor
   SessionTime(string name="", int startHour=0, int startMinute=0)
   {
      Name = name;
      StartHour = startHour;
      StartMinute = startMinute;
      LastProcessedDate = 0;
   }
};

// Class to hold symbol state
class SymbolState : public CObject
{
public:
   string   Symbol;
   bool     WaitingForFirstCandle;
   datetime SessionStartTime;
   bool     OrdersPlaced;
   datetime OrdersPlacedTime;  // New member to track when orders were placed

   // Constructor
   SymbolState(string symbol="")
   {
      Symbol = symbol;
      WaitingForFirstCandle = false;
      SessionStartTime = 0;
      OrdersPlaced = false;
      OrdersPlacedTime = 0;  // Initialize to zero
   }
};

// Arrays to hold sessions and symbol states
CArrayObj *Sessions;
CArrayObj *SymbolStates;

// Trade classes
CTrade         trade;
CPositionInfo  positionInfo;
COrderInfo     orderInfo;

// Function prototypes
void InitializeSessions();
void InitializeSymbols();
bool PlaceOrder(string symbol, ENUM_ORDER_TYPE orderType, double entryPrice, double stopLoss, double takeProfit);
bool HasPendingOrders(string symbol);
void ScheduleNextSessionCheck();
void OnSessionStart();
void OnFirstCandleClose();
datetime GetNextSessionStart();
int DaysInMonth(int year, int month);
void CancelOppositePendingOrder(string symbol, ENUM_ORDER_TYPE executedOrderType);
void CancelAllPendingOrdersForSymbol(string symbol);

// Global variables
datetime NextSessionStartTime = 0;
bool WaitingForFirstCandleClose = false;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   if (!UseDefaultSessions && !UseCustomSessions)
   {
      Print("Error: Either default sessions or custom sessions must be enabled.");
      return(INIT_FAILED);
   }

   Sessions = new CArrayObj();
   SymbolStates = new CArrayObj();

   InitializeSessions();
   InitializeSymbols();

   // Schedule the first session check
   ScheduleNextSessionCheck();

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Clean up Sessions
   if(Sessions!=NULL)
   {
      for(int i=Sessions.Total()-1; i>=0; i--)
      {
         SessionTime* obj = (SessionTime*)Sessions.At(i);
         Sessions.Delete(i);
         delete obj;
      }
      delete Sessions;
      Sessions = NULL;
   }

   // Clean up SymbolStates
   if(SymbolStates!=NULL)
   {
      for(int i=SymbolStates.Total()-1; i>=0; i--)
      {
         SymbolState* obj = (SymbolState*)SymbolStates.At(i);
         SymbolStates.Delete(i);
         delete obj;
      }
      delete SymbolStates;
      SymbolStates = NULL;
   }
}

//+------------------------------------------------------------------+
//| OnTick function                                                  |
//+------------------------------------------------------------------+
void OnTick()
{
   datetime now = TimeCurrent();

   // Check if it's time to start a session
   if (now >= NextSessionStartTime)
   {
      OnSessionStart();
      WaitingForFirstCandleClose = true;

      // Schedule the next session start time
      ScheduleNextSessionCheck();
   }

   // Check if waiting for first candle to close
   if (WaitingForFirstCandleClose)
   {
      datetime firstCandleCloseTime = 0;
      if(SymbolStates.Total() > 0)
      {
         SymbolState *state = (SymbolState*)SymbolStates.At(0);
         firstCandleCloseTime = state.SessionStartTime + 15 * 60; // 15 minutes
      }

      if(now >= firstCandleCloseTime)
      {
         OnFirstCandleClose();
         WaitingForFirstCandleClose = false;
      }
   }

   // Check for pending orders that have not been triggered after an hour
   for (int i = 0; i < SymbolStates.Total(); i++)
   {
      SymbolState *state = (SymbolState*)SymbolStates.At(i);

      // If orders have been placed and there are pending orders
      if (state.OrdersPlaced && HasPendingOrders(state.Symbol))
      {
         // Check if an hour has passed since orders were placed
         if (now - state.OrdersPlacedTime >= 3600) // 3600 seconds = 1 hour
         {
            // Cancel all pending orders for this symbol
            CancelAllPendingOrdersForSymbol(state.Symbol);
            state.OrdersPlaced = false; // Reset the flag
            state.OrdersPlacedTime = 0; // Reset the timestamp
            Print("Pending orders for ", state.Symbol, " have been canceled after one hour.");
         }
      }
   }
}

//+------------------------------------------------------------------+
//| OnSessionStart function                                          |
//+------------------------------------------------------------------+
void OnSessionStart()
{
   datetime now = TimeCurrent();
   MqlDateTime tm;
   TimeToStruct(now, tm);

   // Identify the current session
   for (int s = 0; s < Sessions.Total(); s++)
   {
      SessionTime *session = (SessionTime*)Sessions.At(s);
      if (tm.hour == session.StartHour && tm.min == session.StartMinute)
      {
         // New session started
         session.LastProcessedDate = now;

         // For each symbol, set WaitingForFirstCandle = true
         for (int i = 0; i < SymbolStates.Total(); i++)
         {
            SymbolState *state = (SymbolState*)SymbolStates.At(i);
            state.WaitingForFirstCandle = true;
            state.OrdersPlaced          = false;
            state.SessionStartTime      = now;
            state.OrdersPlacedTime      = 0; // Reset the timestamp
         }
         Print("Session ", session.Name, " started at ", TimeToString(now, TIME_DATE | TIME_SECONDS));
         break;
      }
   }
}

//+------------------------------------------------------------------+
//| OnFirstCandleClose function                                      |
//+------------------------------------------------------------------+
void OnFirstCandleClose()
{
   // For each symbol waiting for the first candle
   for (int i = 0; i < SymbolStates.Total(); i++)
   {
      SymbolState *state = (SymbolState*)SymbolStates.At(i);
      if (state.WaitingForFirstCandle && !state.OrdersPlaced)
      {
         string symbol       = state.Symbol;
         datetime sessionStart = state.SessionStartTime;

         // Get the bar index of the candle that started at sessionStart
         int barIndex = iBarShift(symbol, PERIOD_M15, sessionStart, false);
         if (barIndex >= 0)
         {
            datetime candleTime = iTime(symbol, PERIOD_M15, barIndex);
            // Check if the candle has closed
            datetime candleCloseTime = candleTime + 15 * 60;
            datetime now = TimeCurrent();
            if (now >= candleCloseTime)
            {
               // Candle has closed
               state.WaitingForFirstCandle = false;

               // Get candle data
               double high = iHigh(symbol, PERIOD_M15, barIndex);
               double low  = iLow(symbol, PERIOD_M15, barIndex);

               // Calculate entry prices, SL, TP
               int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
               double entryBuy = NormalizeDouble(high, digits);
               double entrySell = NormalizeDouble(low, digits);
               double slBuy = NormalizeDouble(low, digits);
               double tpBuy = NormalizeDouble(high + (high - low) * RiskRewardRatio, digits);
               double slSell = NormalizeDouble(high, digits);
               double tpSell = NormalizeDouble(low - (high - low) * RiskRewardRatio, digits);

               // Before placing orders, check if there are existing pending orders
               if (HasPendingOrders(symbol))
               {
                  Print("Existing pending orders found for ", symbol, ". Skipping order placement.");
                  state.OrdersPlaced = true;
                  continue;
               }

               // Place buy stop and sell stop orders
               bool buyOrderPlaced  = PlaceOrder(symbol, ORDER_TYPE_BUY_STOP, entryBuy, slBuy, tpBuy);
               bool sellOrderPlaced = PlaceOrder(symbol, ORDER_TYPE_SELL_STOP, entrySell, slSell, tpSell);
               if (buyOrderPlaced || sellOrderPlaced)
               {
                  state.OrdersPlaced = true;
                  state.OrdersPlacedTime = TimeCurrent();  // Record the time when orders were placed
                  PrintFormat("Orders placed for %s - Buy Stop at %.5f, SL: %.5f, TP: %.5f | Sell Stop at %.5f, SL: %.5f, TP: %.5f",
                              symbol, entryBuy, slBuy, tpBuy, entrySell, slSell, tpSell);
               }
            }
         }
         else
         {
            Print("Could not find the candle for ", symbol, " at session start time.");
         }
      }
   }
}

//+------------------------------------------------------------------+
//| ScheduleNextSessionCheck function                                |
//+------------------------------------------------------------------+
void ScheduleNextSessionCheck()
{
   NextSessionStartTime = GetNextSessionStart();
   Print("Next session starts at ", TimeToString(NextSessionStartTime, TIME_DATE | TIME_SECONDS));
}

//+------------------------------------------------------------------+
//| GetNextSessionStart function                                     |
//+------------------------------------------------------------------+
datetime GetNextSessionStart()
{
   datetime now = TimeCurrent();
   MqlDateTime tmNow;
   TimeToStruct(now, tmNow);

   datetime earliestTime = 0;

   // Loop through all sessions to find the next start time
   for (int s = 0; s < Sessions.Total(); s++)
   {
      SessionTime *session = (SessionTime*)Sessions.At(s);
      MqlDateTime tmSession;

      // Ensure all date fields are properly set
      tmSession.year = tmNow.year;
      tmSession.mon  = tmNow.mon;
      tmSession.day  = tmNow.day;
      tmSession.hour = session.StartHour;
      tmSession.min  = session.StartMinute;
      tmSession.sec  = 0;

      datetime sessionStart = StructToTime(tmSession);

      // If the session start time is before now, increment the day correctly
      if (sessionStart <= now)
      {
         // Increment the day, handling month/year rollovers
         tmSession.day += 1;
         // Adjust for month/year rollover
         int daysInMonth = DaysInMonth(tmSession.year, tmSession.mon);
         if (tmSession.day > daysInMonth)
         {
            tmSession.day = 1;
            tmSession.mon += 1;
            if (tmSession.mon > 12)
            {
               tmSession.mon = 1;
               tmSession.year += 1;
            }
         }
         sessionStart = StructToTime(tmSession);
      }

      if (earliestTime == 0 || sessionStart < earliestTime)
      {
         earliestTime = sessionStart;
      }
   }

   return earliestTime;
}

//+------------------------------------------------------------------+
//| DaysInMonth function                                             |
//+------------------------------------------------------------------+
int DaysInMonth(int year, int month)
{
   switch (month)
   {
      case 1: case 3: case 5: case 7: case 8: case 10: case 12:
         return 31;
      case 4: case 6: case 9: case 11:
         return 30;
      case 2:
         // Check for leap year
         if ((year % 4 == 0 && year % 100 != 0) || (year % 400 == 0))
            return 29;
         else
            return 28;
      default:
         return 0; // Invalid month
   }
}

//+------------------------------------------------------------------+
//| Initialize trading sessions                                      |
//+------------------------------------------------------------------+
void InitializeSessions()
{
   Sessions.Clear();
   if (UseDefaultSessions)
   {
      Sessions.Add(new SessionTime("Tokyo", 0, 0));
      Sessions.Add(new SessionTime("London", 8, 0));
      Sessions.Add(new SessionTime("New York", 13, 0));
      Sessions.Add(new SessionTime("Sydney", 22, 0));
      Sessions.Add(new SessionTime("Singapore", 1, 0));
   }

   if (UseCustomSessions)
   {
      string sessionsList[];
      int sessionCount = StringSplit(CustomSessions, ';', sessionsList);
      for (int i = 0; i < sessionCount; i++)
      {
         string sessionData[]; // Name,StartHour,StartMinute
         int dataCount = StringSplit(sessionsList[i], ',', sessionData);
         if (dataCount == 3)
         {
            string name = sessionData[0];
            int startHour = (int)StringToInteger(sessionData[1]);
            int startMinute = (int)StringToInteger(sessionData[2]);
            Sessions.Add(new SessionTime(name, startHour, startMinute));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Initialize symbols                                               |
//+------------------------------------------------------------------+
void InitializeSymbols()
{
   SymbolStates.Clear();
   string symbolsList[];
   int symbolCount = StringSplit(Symbols, ',', symbolsList);
   if (symbolCount == 0)
   {
      // If no symbols provided, default to the current chart symbol
      SymbolStates.Add(new SymbolState(_Symbol));
   }
   else
   {
      for (int i = 0; i < symbolCount; i++)
      {
         string symbolName = symbolsList[i];
         StringTrimLeft(symbolName);
         StringTrimRight(symbolName);
         if (SymbolSelect(symbolName, true))
         {
            SymbolStates.Add(new SymbolState(symbolName));
         }
         else
         {
            Print("Symbol not found or could not be selected: ", symbolName);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Place order function using CTrade class                          |
//+------------------------------------------------------------------+
bool PlaceOrder(string symbol, ENUM_ORDER_TYPE orderType, double entryPrice, double stopLoss, double takeProfit)
{
   trade.SetExpertMagicNumber(MAGIC_NUMBER);
   trade.SetTypeFilling(ORDER_FILLING_FOK);

   // Validate lot size
   double minLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   double volume  = LotSize;

   if (volume < minLot)
      volume = minLot;
   if (volume > maxLot)
      volume = maxLot;
   volume = MathFloor(volume / lotStep) * lotStep;

   // Adjust prices to tick size
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   entryPrice = NormalizeDouble(entryPrice, digits);
   stopLoss   = NormalizeDouble(stopLoss, digits);
   takeProfit = NormalizeDouble(takeProfit, digits);

   // Place order
   bool result = false;
   switch (orderType)
   {
      case ORDER_TYPE_BUY_STOP:
         result = trade.BuyStop(volume, entryPrice, symbol, stopLoss, takeProfit, ORDER_TIME_GTC);
         break;
      case ORDER_TYPE_SELL_STOP:
         result = trade.SellStop(volume, entryPrice, symbol, stopLoss, takeProfit, ORDER_TIME_GTC);
         break;
      default:
         Print("Invalid order type.");
         return false;
   }

   if (!result)
   {
      Print("OrderSend failed: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
      return false;
   }
   else
   {
      Print("Order placed successfully: ", symbol, " ", EnumToString(orderType), " at ", entryPrice);
      return true;
   }
}

//+------------------------------------------------------------------+
//| Check for existing pending orders                                |
//+------------------------------------------------------------------+
bool HasPendingOrders(string symbol)
{
   uint totalOrders = OrdersTotal();

   for (uint i = 0; i < totalOrders; i++)
   {
      ulong ticket = OrderGetTicket(i);
      if (orderInfo.Select(ticket))
      {
         if (orderInfo.Symbol() == symbol && orderInfo.Magic() == MAGIC_NUMBER)
         {
            ENUM_ORDER_TYPE orderType = orderInfo.Type();
            // Check if it's a pending order
            if (orderType == ORDER_TYPE_BUY ||
                orderType == ORDER_TYPE_SELL )
            {
               return true; // Found a pending order
            }
         }
      }
   }
   return false; // No pending orders found
}

//+------------------------------------------------------------------+
//| Cancel Opposite Pending Order                                    |
//+------------------------------------------------------------------+
void CancelOppositePendingOrder(string symbol, ENUM_ORDER_TYPE executedOrderType)
{
   uint totalOrders = OrdersTotal();

   for (uint i = 0; i < totalOrders; i++)
   {
      ulong ticket = OrderGetTicket(i);
      if (orderInfo.Select(ticket))
      {
         if (orderInfo.Symbol() == symbol && orderInfo.Magic() == MAGIC_NUMBER)
         {
            ENUM_ORDER_TYPE orderType = orderInfo.Type();
            // Identify the opposite order type
            if ((executedOrderType == ORDER_TYPE_BUY_STOP && orderType == ORDER_TYPE_SELL) ||
                (executedOrderType == ORDER_TYPE_SELL_STOP && orderType == ORDER_TYPE_BUY))
            {
               // Cancel the opposite pending order using CTrade
 
               if (trade.OrderDelete(ticket))
               {
                  Print("Canceled opposite pending order: Ticket ", ticket, " on ", symbol);
               }
               else
               {
                  Print("Failed to cancel opposite pending order: Ticket ", ticket, " on ", symbol,
                        " Error: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
               }
               break; // Exit after canceling the opposite order
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Cancel All Pending Orders for Symbol                             |
//+------------------------------------------------------------------+
void CancelAllPendingOrdersForSymbol(string symbol)
{
   uint totalOrders = OrdersTotal();

   for (uint i = 0; i < totalOrders; i++)
   {
      ulong ticket = OrderGetTicket(i);
      if (orderInfo.Select(ticket))
      {
         if (orderInfo.Symbol() == symbol && orderInfo.Magic() == MAGIC_NUMBER)
         {
            ENUM_ORDER_TYPE orderType = orderInfo.Type();
            // Check if it's a pending order
            if (orderType == ORDER_TYPE_BUY || orderType == ORDER_TYPE_SELL ||
                orderType == ORDER_TYPE_BUY_LIMIT || orderType == ORDER_TYPE_SELL_LIMIT ||
                orderType == ORDER_TYPE_BUY_STOP_LIMIT || orderType == ORDER_TYPE_SELL_STOP_LIMIT)
            {
               // Cancel the pending order using CTrade
               if (trade.OrderDelete(ticket))
               {
                  Print("Canceled pending order: Ticket ", ticket, " on ", symbol);
               }
               else
               {
                  Print("Failed to cancel pending order: Ticket ", ticket, " on ", symbol,
                        " Error: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| OnTradeTransaction function                                      |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans, const MqlTradeRequest& request, const MqlTradeResult& result)
{
   // Check if the transaction is a new deal added
   if (trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      ulong dealTicket = trans.deal;

      // Select the deal from history
      if (HistoryDealSelect(dealTicket))
      {
         // Check if the deal is an entry into a position
         if (HistoryDealGetInteger(dealTicket, DEAL_ENTRY) == DEAL_ENTRY_IN)
         {
            // Get deal properties
            string symbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
            ulong magicNumber = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);

            // Verify that the deal is from our EA
            if (magicNumber != MAGIC_NUMBER)
               return; // Not our deal

            ENUM_DEAL_TYPE dealType = (ENUM_DEAL_TYPE)HistoryDealGetInteger(dealTicket, DEAL_TYPE);
            ENUM_ORDER_TYPE executedOrderType;

            // Determine the executed order type
            if (dealType == DEAL_TYPE_BUY)
               executedOrderType = ORDER_TYPE_BUY_STOP;
            else if (dealType == DEAL_TYPE_SELL)
               executedOrderType = ORDER_TYPE_SELL_STOP;
            else
               return; // Not a buy or sell deal

            // Now cancel the opposite pending order
            CancelOppositePendingOrder(symbol, executedOrderType);
         }
      }
   }
}
