﻿// The procedure performs document posting
//
Procedure Posting(Cancel, Mode)
		
	PostingCost = 0;
	
	// create a value table for posting amounts
	
	PostingDatasetIncome = New ValueTable();
	PostingDatasetIncome.Columns.Add("IncomeAccount");
	PostingDatasetIncome.Columns.Add("AmountRC");
	
	PostingDatasetCOGS = New ValueTable();
	PostingDatasetCOGS.Columns.Add("COGSAccount");
	PostingDatasetCOGS.Columns.Add("AmountRC");	
	
	PostingDatasetInvOrExp = New ValueTable();
	PostingDatasetInvOrExp.Columns.Add("InvOrExpAccount");
    PostingDatasetInvOrExp.Columns.Add("AmountRC");		
	
	// create an Inventory Journal dataset
	
	InvDataset = InventoryCosting.SalesDocumentsDataset(Ref, Location);
	
	// update location balances
	
	RegisterRecords.LocationBalances.Write = True;
	For Each CurRowLineItems In LineItems Do
		If CurRowLineItems.Product.Type = Enums.InventoryTypes.Inventory Then
			Record = RegisterRecords.LocationBalances.Add();
			Record.RecordType = AccumulationRecordType.Expense;
			Record.Period = Date;
			Record.Product = CurRowLineItems.Product;
			Record.Location = Location;
			Record.QtyOnHand = CurRowLineItems.Quantity;
		EndIf;	
	EndDo;

	For Each CurRowLineItems In LineItems Do
				
		If CurRowLineItems.Product.Type = Enums.InventoryTypes.Inventory Then				
						
			// check inventory balances and cancel if not sufficient
			
			CurrentBalance = InventoryCosting.LocationBalance(CurRowLineItems.Product, Location);	
			If CurRowLineItems.Quantity > CurrentBalance Then					
				Message = New UserMessage();
				Message.Text=NStr("en='Insufficient balance'");
				Message.Message();
				Cancel = True;
				Return;
			EndIf;

		EndIf;
			
		If CurRowLineItems.Product.Type = Enums.InventoryTypes.Inventory Then
			
			// update the issued amount of the parent sales order
			
			If NOT ParentSalesOrder.IsEmpty() Then
				Filter = New Structure("Product");
				Filter.Insert("Product", CurRowLineItems.Product);	
				Doc = ParentSalesOrder.GetObject();
				Row = Doc.LineItems.FindRows(Filter)[0];
				Row.Issued = Row.Issued + CurRowLineItems.Quantity;
				Doc.Write();
			EndIf;				
		EndIf;
		
		// select a subset of the Inventory Journal dataset and call the inventory costing procedure
		
		Filter = New Structure();
		Filter.Insert("Product", CurRowLineItems.Product); 
		InvDataset.Sort("Date, Row");
		InvDatasetProduct = InvDataset.FindRows(Filter);

		PostingCost = InventoryCosting.SalesDocumentProcessing(CurRowLineItems, InvDatasetProduct, Location);
		
		// fill in the account posting value table with amounts
		
		PostingLineIncome = PostingDatasetIncome.Add();
		If CurRowLineItems.Product.Code = "" Then
			PostingLineIncome.IncomeAccount = Company.IncomeAccount;	
		Else	
			PostingLineIncome.IncomeAccount = CurRowLineItems.Product.IncomeAccount;
		EndIf;	
		PostingLineIncome.AmountRC = CurRowLineItems.Price * ExchangeRate * CurRowLineItems.Quantity;
		
		If CurRowLineItems.Product.Type = Enums.InventoryTypes.Inventory Then 
			PostingLineCOGS = PostingDatasetCOGS.Add();
			PostingLineCOGS.COGSAccount = CurRowLineItems.Product.COGSAccount;
			PostingLineCOGS.AmountRC = PostingCost;
			
			PostingLineInvOrExp = PostingDatasetInvOrExp.Add();
			PostingLineInvOrExp.InvOrExpAccount = CurRowLineItems.Product.InventoryOrExpenseAccount;
			PostingLineInvOrExp.AmountRC = PostingCost;
		EndIf;
		
		PostingCost = 0;
		
	EndDo;
	
	// GL posting
	
    RegisterRecords.GeneralJournal.Write = True;	
    			
	Record = RegisterRecords.GeneralJournal.AddDebit();
	Record.Account = ARAccount;
	Record.Period = Date;
	Record.Currency = Currency;
	Record.Amount = DocumentTotal;
	Record.AmountRC = DocumentTotal * ExchangeRate;		
	Record.ExtDimensions[ChartsOfCharacteristicTypes.Dimensions.Company] = Company;
	Record.ExtDimensions[ChartsOfCharacteristicTypes.Dimensions.Document] = Ref;
	
	PostingDatasetIncome.GroupBy("IncomeAccount", "AmountRC");
	NoOfPostingRows = PostingDatasetIncome.Count();
	For i = 0 To NoOfPostingRows - 1 Do			
		Record = RegisterRecords.GeneralJournal.AddCredit();
		Record.Account = PostingDatasetIncome[i][0];
		Record.Period = Date;
		Record.AmountRC = PostingDatasetIncome[i][1];				
	EndDo;

	PostingDatasetCOGS.GroupBy("COGSAccount", "AmountRC");
	NoOfPostingRows = PostingDatasetCOGS.Count();
	For i = 0 To NoOfPostingRows - 1 Do			
		Record = RegisterRecords.GeneralJournal.AddDebit();
		Record.Account = PostingDatasetCOGS[i][0];
		Record.Period = Date;
		Record.AmountRC = PostingDatasetCOGS[i][1];				
	EndDo;

	PostingDatasetInvOrExp.GroupBy("InvOrExpAccount", "AmountRC");
	NoOfPostingRows = PostingDatasetInvOrExp.Count();
	For i = 0 To NoOfPostingRows - 1 Do			
		Record = RegisterRecords.GeneralJournal.AddCredit();
		Record.Account = PostingDatasetInvOrExp[i][0];
		Record.Period = Date;
		Record.AmountRC = PostingDatasetInvOrExp[i][1];				
	EndDo;
			
	If SalesTax > 0 Then
		Record = RegisterRecords.GeneralJournal.AddCredit();
		Record.Account = Constants.SalesTaxPayableAccount.Get();
		Record.Period = Date;
		Record.AmountRC = SalesTax * ExchangeRate;
	EndIf;		
	
	If VATTotal > 0 Then
		Record = RegisterRecords.GeneralJournal.AddCredit();
		Record.Account = Constants.VATAccount.Get();
		Record.Period = Date;
		Record.AmountRC = VATTotal;
	EndIf;

	
EndProcedure


// The procedure prepopulates a sales invoice when created from a sales order.
//
Procedure Filling(FillingData, StandardProcessing)

	If TypeOf(FillingData) = Type("DocumentRef.SalesOrder") Then
		Company = FillingData.Company;
		DocumentTotal = FillingData.DocumentTotal;
		DocumentTotalRC = FillingData.DocumentTotalRC;
		ParentSalesOrder = FillingData.Ref;
		SalesTax = FillingData.SalesTax;
		Currency = FillingData.Currency;
		ExchangeRate = FillingData.ExchangeRate;
		Location = FillingData.Location;
		VATTotal = FillingData.VATTotal;
		ARAccount = FillingData.Company.DefaultCurrency.DefaultARAccount;
		
		For Each CurRowLineItems In FillingData.LineItems Do
			NewRow = LineItems.Add();
			NewRow.LineTotal = CurRowLineItems.LineTotal;
			NewRow.Price = CurRowLineItems.Price;
			NewRow.Product = CurRowLineItems.Product;
			NewRow.Descr = CurRowLineItems.Descr;
			NewRow.Quantity = CurRowLineItems.Quantity;
			NewRow.QuantityUM = CurRowLineItems.QuantityUM;
			NewRow.UM = CurRowLineItems.UM;
			NewRow.SalesTaxType = CurRowLineItems.SalesTaxType;
			NewRow.TaxableAmount = CurRowLineItems.TaxableAmount;
			NewRow.VAT = CurRowLineItems.VAT;
			NewRow.VATCode = CurRowLineItems.VATCode;
		EndDo;
		
	EndIf;
	
EndProcedure

// The procedure prevents voiding if the Allow Voiding functional option is disabled.
//
Procedure UndoPosting(Cancel)
	
	If InventoryCosting.InventoryPresent(Ref) Then
	
		If NOT GetFunctionalOption("AllowVoiding") Then
			
			Message = New UserMessage();
			Message.Text = NStr("en='You cannot void a posted document with inventory items'");
			Message.Message();
			Cancel = True;
			Return;
			
		EndIf;

	EndIf;	
	
EndProcedure

// The procedure prevents re-posting if the Allow Voiding functional option is disabled.
//
Procedure BeforeWrite(Cancel, WriteMode, PostingMode)
	
	If InventoryCosting.InventoryPresent(Ref) Then
		
		If NOT GetFunctionalOption("AllowVoiding") Then
			
			If WriteMode = DocumentWriteMode.Posting Then
				
				If DocPosted Then
			       Message = New UserMessage();
			       Message.Text = NStr("en='You cannot re-post a posted document with inventory items'");
			       Message.Message();
			       Cancel = True;
			       Return;
			    Else
			       DocPosted = True;
			   EndIf;
			   
		   EndIf;
		
		EndIf;
		
	EndIf;	

EndProcedure

// Clears the DocPosted attribute on document copying
//
Procedure OnCopy(CopiedObject)
	DocPosted = False;
EndProcedure





