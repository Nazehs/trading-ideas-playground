//+------------------------------------------------------------------+
//|                                      CCI Forex EA.mq5           |
//|                                      Copyright 2024, Nazeh Abel  |
//|                                             https://www.openlabtechnologies.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Nazeh Abel"
#property link      "https://www.openlabtechnologies.com"
#property version   "1.00"

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>

#define SIGNAL_BUY    1             // Buy signal
#define SIGNAL_NOT    0             // no trading signal
#define SIGNAL_SELL  -1             // Sell signal

#define CLOSE_LONG    2             // signal to close Long
#define CLOSE_SHORT  -2             // signal to close Short

//--- Input parameters
input int InpPeriodCCI     = 40;    // CCI period 20
input ENUM_APPLIED_PRICE InpPrice=PRICE_OPEN; // price type PRICE_CLOSE
input double InpCCILevel = 100;   // CCI overbought/oversold level

//--- trade parameters
input uint InpDuration =93;         // position holding time in bars 20
input uint InpSlippage = 100;         // slippage in points
input double takeProfitPercentage = 0.07; // 2% take profit
input double stopLossPercentage = 0.061; // 1% stop loss
input double trailingStopLossPercentage = 0.0025; // 0.25% trailing stop loss
input double trailingStopTriggerPoints = 2000;
input double DrawdownPercent  = 10.0;          // Drawdown percentage threshold
input bool  useMaxDrawDownOnTrade = true;      // close trade based on maximimum allowed drawdown

//--- money management parameters
input double InpLot=0.3;            // lot
//--- Expert ID
input long InpMagicNumber=130100;   // Magic Number

//--- global variables
int    ExtSignalOpen     =0;        // Buy/Sell signal
int    ExtSignalClose    =0;        // signal to close a position
string ExtDirection      ="";       // position opening direction
bool   ExtCloseByTime    =true;     // requires closing by time
//---  indicator handle
int    ExtIndicatorHandle=INVALID_HANDLE;
CPositionInfo positionInfo; // Object for position information

//--- service objects
CSymbolInfo ExtSymbolInfo;
CTrade trade; // For trade operations

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- set parameters for trading operations
//trade.SetDeviationInPoints(InpSlippage);    // slippage
   trade.SetExpertMagicNumber(InpMagicNumber); // Expert Advisor ID
   trade.LogLevel(LOG_LEVEL_ERRORS);           // logging level

//--- indicator initialization
   ExtIndicatorHandle=iCCI(_Symbol, _Period, InpPeriodCCI, InpPrice);
   if(ExtIndicatorHandle==INVALID_HANDLE)
     {
      Print("Error creating CCI indicator");
      return(INIT_FAILED);
     }
//--- OK
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//--- release indicator handle
   IndicatorRelease(ExtIndicatorHandle);
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//--- save the next bar start time; all checks at bar opening only
   static datetime next_bar_open=0;
// Update trailing stop loss
   //ManageTrailingStop();
//--- Phase 1 - check the emergence of a new bar and update the status
   if(TimeCurrent()>=next_bar_open)
     {
      //--- get the current state of environment on the new bar
      // namely, set the values of global variables:
      // ExtSignalOpen - signal to open
      // ExtSignalClose - signal to close
      // ExtPatternInfo - current pattern information
      if(CheckState())
        {
         //--- set the new bar opening time
         next_bar_open=TimeCurrent();
         next_bar_open-=next_bar_open%PeriodSeconds(_Period);
         next_bar_open+=PeriodSeconds(_Period);


        }

      //--- Phase 2 - if there is a signal and no position in this direction
      if(ExtSignalOpen && !PositionExist(ExtSignalOpen))
        {
         Print("\r\nSignal to open position ", ExtDirection);
         PositionOpen();
         if(PositionExist(ExtSignalOpen))
            ExtSignalOpen=SIGNAL_NOT;
        }

      //--- Phase 3 - close if there is a signal to close
      if(ExtSignalClose && PositionExist(ExtSignalClose))
        {
         Print("\r\nSignal to close position ", ExtDirection);
         CloseBySignal(ExtSignalClose);
         if(!PositionExist(ExtSignalClose))
            ExtSignalClose=SIGNAL_NOT;
        }

      //--- Phase 4 - close upon expiration
      if(ExtCloseByTime && PositionExpiredByTimeExist())
        {
         CloseByTime();
         ExtCloseByTime=PositionExpiredByTimeExist();
        }
     }
  }
//+------------------------------------------------------------------+
//|  Get the current environment and check for a pattern             |
//+------------------------------------------------------------------+
bool CheckState()
  {
//--- check if there is a signal to close a position
   if(!CheckCloseSignal())
     {
      Print("Error, failed to check the closing signal");
      return(false);
     }

//--- if positions are to be closed after certain holding time in bars
   if(InpDuration)
      ExtCloseByTime=true; // set flag to close upon expiration

//--- all checks done
   return(true);
  }
//+------------------------------------------------------------------+
//| Open a position in the direction of the signal                   |
//+------------------------------------------------------------------+
bool PositionOpen()
  {
   ExtSymbolInfo.Refresh();
   ExtSymbolInfo.RefreshRates();
//--- Stop Loss and Take Profit are not set by default
   double tp=0.0;
   double sl =0.0;
   double price=0.0;

   int    digits=ExtSymbolInfo.Digits();
   double point=ExtSymbolInfo.Point();

//--- uptrend
   if(ExtSignalOpen==SIGNAL_BUY)
     {
      price=NormalizeDouble(ExtSymbolInfo.Ask(), digits);
      tp = NormalizeDouble(price + (takeProfitPercentage * price), _Digits);
      sl = NormalizeDouble(price - (stopLossPercentage * price), _Digits);
      if(!trade.Buy(InpLot, _Symbol, price, sl, tp))
        {
         PrintFormat("Failed %s buy %G at %G (sl=%G tp=%G) failed. Ask=%G error=%d",
                     _Symbol, InpLot, price, sl, tp, ExtSymbolInfo.Ask(), GetLastError());
         return(false);
        }
     }

//--- downtrend
   if(ExtSignalOpen==SIGNAL_SELL)
     {
      price=NormalizeDouble(ExtSymbolInfo.Bid(), digits);
      tp = NormalizeDouble(price - (takeProfitPercentage * price), _Digits);
      sl = NormalizeDouble(price + (stopLossPercentage * price), _Digits);
      if(!trade.Sell(InpLot, _Symbol, price,  sl, tp))
        {
         PrintFormat("Failed %s sell at %G (sl=%G tp=%G) failed. Bid=%G error=%d",
                     _Symbol, price, sl, tp, ExtSymbolInfo.Bid(), GetLastError());
         trade.PrintResult();
         Print("   ");
         return(false);
        }
     }

   return(true);
  }
//+------------------------------------------------------------------+
//|  Close a position based on the specified signal                  |
//+------------------------------------------------------------------+
void CloseBySignal(int type_close)
  {
//--- if there is no signal to close, return successful completion
   if(type_close==SIGNAL_NOT)
      return;
//--- if there are no positions opened by our EA
   if(PositionExist(ExtSignalClose)==0)
      return;

//--- closing direction
   long type;
   switch(type_close)
     {
      case CLOSE_SHORT:
         type=POSITION_TYPE_SELL;
         break;
      case CLOSE_LONG:
         type=POSITION_TYPE_BUY;
         break;
      default:
         Print("Error! Signal to close not detected");
         return;
     }

//--- check all positions and close ours based on the signal
   int positions=PositionsTotal();
   for(int i=positions-1; i>=0; i--)
     {
      ulong ticket=PositionGetTicket(i);
      positionInfo.SelectByIndex(i);
      if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == InpMagicNumber)
        {
         if(positionInfo.PositionType()==type)
           {
            trade.PositionClose(ticket, InpSlippage);
            trade.PrintResult();
            Print("   ");
           }
        }
     }
  }
//+------------------------------------------------------------------+
//|  Close positions upon holding time expiration in bars            |
//+------------------------------------------------------------------+
void CloseByTime()
  {
//--- if there are no positions opened by our EA
   if(PositionExist(ExtSignalOpen)==0)
      return;

//--- check all positions and close ours based on the holding time in bars
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      positionInfo.SelectByIndex(i);
      //--- if they correspond to our values
      if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == InpMagicNumber)
        {
         //--- position opening time
         datetime open_time=(datetime)PositionGetInteger(POSITION_TIME);
         //--- check position holding time in bars
         if(BarsHold(open_time)>=(int)InpDuration)
           {
            Print("\r\nTime to close position #", positionInfo.Ticket());
            trade.PositionClose(positionInfo.Ticket(), InpSlippage);
            trade.PrintResult();
           }
        }
     }
  }
//+------------------------------------------------------------------+
//| Returns true if there are open positions                         |
//+------------------------------------------------------------------+
bool PositionExist(int signal_direction)
  {
   bool check_type=(signal_direction!=SIGNAL_NOT);

//--- what positions to search
   ENUM_POSITION_TYPE search_type=WRONG_VALUE;
   if(check_type)
      switch(signal_direction)
        {
         case SIGNAL_BUY:
            search_type=POSITION_TYPE_BUY;
            break;
         case SIGNAL_SELL:
            search_type=POSITION_TYPE_SELL;
            break;
         case CLOSE_LONG:
            search_type=POSITION_TYPE_BUY;
            break;
         case CLOSE_SHORT:
            search_type=POSITION_TYPE_SELL;
            break;
         default:
            //--- entry direction is not specified; nothing to search
            return(false);
        }

//--- go through the list of all positions
   for(int i=0; i<PositionsTotal(); i++)
     {
      if(PositionGetTicket(i)!=0)
        {
         //--- if the position type does not match, move on to the next one
         ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         if(check_type && (type!=search_type))
            continue;
         //--- get the name of the symbol and the expert id (magic number)
         string symbol =PositionGetString(POSITION_SYMBOL);
         long   magic  =PositionGetInteger(POSITION_MAGIC);
         //--- if they correspond to our values
         if(symbol==Symbol() && magic==InpMagicNumber)
           {
            //--- yes, this is the right position, stop the search
            return(true);
           }
        }
     }

//--- open position not found
   return(false);
  }
//+------------------------------------------------------------------+
//| Returns true if there are open positions with expired time       |
//+------------------------------------------------------------------+
bool PositionExpiredByTimeExist()
  {
//--- go through the list of all positions
   for(int i=0; i<PositionsTotal(); i++)
     {
      if(PositionGetTicket(i)!=0)
        {
         //--- get the name of the symbol and the expert id (magic number)
         string symbol =PositionGetString(POSITION_SYMBOL);
         long   magic  =PositionGetInteger(POSITION_MAGIC);
         //--- if they correspond to our values
         if(symbol==Symbol() && magic==InpMagicNumber)
           {
            //--- position opening time
            datetime open_time=(datetime)PositionGetInteger(POSITION_TIME);
            //--- check position holding time in bars
            int check=BarsHold(open_time);
            //--- id the value is -1, the check completed with an error
            if(check==-1 || (BarsHold(open_time)>=(int)InpDuration))
               return(true);
           }
        }
     }
//--- open position not found
   return(false);
  }
//+------------------------------------------------------------------+
//| Checks position closing time in bars                             |
//+------------------------------------------------------------------+
int BarsHold(datetime open_time)
  {
//--- first run a basic simple check
   if(TimeCurrent()-open_time<PeriodSeconds(_Period))
     {
      //--- opening time is inside the current bar
      return(0);
     }
//---
   MqlRates bars[];
   if(CopyRates(_Symbol, _Period, open_time, TimeCurrent(), bars)==-1)
     {
      Print("Error. CopyRates() failed, error = ", GetLastError());
      return(-1);
     }
//--- check position holding time in bars
   return(ArraySize(bars));
  }

//+------------------------------------------------------------------+
//| Check if there is a signal to close                              |
//+------------------------------------------------------------------+
bool CheckCloseSignal()
  {
   ExtSignalClose=false;
//--- if there is a signal to enter the market, do not check the signal to close
   if(ExtSignalOpen!=SIGNAL_NOT)
      return(true);

// CCI close signals - for example, you could close when CCI crosses a threshold:
   if(CCI(1) > InpCCILevel)
     {
      ExtSignalClose = CLOSE_LONG;
      ExtDirection = "Long";
     }
   else
      if(CCI(1) < -InpCCILevel)
        {
         ExtSignalClose = CLOSE_SHORT;
         ExtDirection = "Short";
        }

// Check for entry signals
   if(CCI(1) < -InpCCILevel && CCI(0) > -InpCCILevel)
     {
      ExtSignalOpen = SIGNAL_BUY;
      ExtDirection = "Long";
     }
   else
      if(CCI(1) > InpCCILevel && CCI(0) < InpCCILevel)
        {
         ExtSignalOpen = SIGNAL_SELL;
         ExtDirection = "Short";
        }

   return(true);
  }
//+------------------------------------------------------------------+
//| CCI indicator value at the specified bar                         |
//+------------------------------------------------------------------+
double CCI(int index)
  {
   double indicator_values[];
   if(CopyBuffer(ExtIndicatorHandle, 0, index, 1, indicator_values)<0)
     {
      //--- if the copying fails, report the error code
      PrintFormat("Failed to copy data from the CCI indicator, error code %d", GetLastError());
      return(EMPTY_VALUE);
     }
   return(indicator_values[0]);
  }
  
  //+------------------------------------------------------------------+
//| Manage trailing stop loss                                         |
//+------------------------------------------------------------------+
void ManageTrailingStop()
  {
  double trailingStopLossPoints = 2000;
  //double trailingStopTriggerPoints = 2500;
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
               double newStopLoss = NormalizeDouble(currentPrice - (currentPrice * trailingStopLossPercentage), _Digits);
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
                  double newStopLoss = NormalizeDouble(currentAsk + (currentAsk * trailingStopLossPercentage), _Digits);
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

      if(positionLoss < 0 && MathAbs(positionLoss) >= drawdownLimit && positionInfo.Magic() == InpMagicNumber)
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