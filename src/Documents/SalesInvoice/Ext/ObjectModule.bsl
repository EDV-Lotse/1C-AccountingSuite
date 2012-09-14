﻿// The procedure performs document posting
//
Procedure Posting(Cancel, Mode)
		
	PostingCost = 0;
		
	For Each CurRowLineItems In LineItems Do			
		If CurRowLineItems.Product.Type = Enums.InventoryTypes.Inventory Then
			
			// update the issued and invoiced amount of the parent sales order
			
			If NOT ParentSalesOrder.IsEmpty() Then
				Filter = New Structure("Product");
				Filter.Insert("Product", CurRowLineItems.Product);	
				Doc = ParentSalesOrder.GetObject();
				Row = Doc.LineItems.FindRows(Filter)[0];
				Row.Invoiced = Row.Invoiced + CurRowLineItems.Quantity;
				If ParentGoodsIssue.IsEmpty() Then
					Row.Issued = Row.Issued + CurRowLineItems.Quantity;
				EndIf;	
				Doc.Write();
			EndIf;				
		EndIf;
	EndDo;	
	
	If ParentGoodsIssue.IsEmpty() Then
		
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
					Cancel = True;
					Message = New UserMessage();
					Message.Text=NStr("en='Insufficient balance'");
					Message.Message();
					Return;
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
		
	EndIf;
	
	
	If NOT ParentGoodsIssue.IsEmpty() Then
		
		// updating the parent's goods issue GL posting
		
		Reg = AccountingRegisters.GeneralJournal.CreateRecordSet();
		Reg.Filter.Recorder.Set(ParentGoodsIssue);
		Reg.Read();
		
			For Each Transaction In Reg Do
				
				Transaction.Period = Date;
				Transaction.Recorder = Ref;
				If NOT Transaction.ExtDimensions[ChartsOfCharacteristicTypes.Dimensions.Document] = Undefined Then
					Transaction.ExtDimensions[ChartsOfCharacteristicTypes.Dimensions.Document] = Ref;
				EndIf;
				
			EndDo;
			
		Reg.Write();
		
	EndIf;
	
	If ParentGoodsIssue.IsEmpty() Then
		
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
		
	EndIf;
	 	 	
EndProcedure


// The procedure prepopulates a sales invoice when created from a sales quote, sales order, or goods issue.
//
Procedure Filling(FillingData, StandardProcessing)

	If TypeOf(FillingData) = Type("DocumentRef.SalesQuote") Then
		Company = FillingData.Company;
		DocumentTotal = FillingData.DocumentTotal;
		DocumentTotalRC = FillingData.DocumentTotalRC;
		ParentSalesOrder = FillingData.Ref;
		SalesTax = FillingData.SalesTax;
		Currency = FillingData.Currency;
		ExchangeRate = FillingData.ExchangeRate;
		Location = FillingData.Location;
		VATTotal = FillingData.VATTotal;
		Bank = FillingData.Bank;
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
			NewRow.VATCode = CurRowLineItems.VAT;
		EndDo;
		
	EndIf;

	
	If TypeOf(FillingData) = Type("DocumentRef.SalesOrder") Then
		
		// Check if Goods Issues exist. If found - cancel.
		Query = New Query("SELECT
		                  |	GoodsIssue.Ref
		                  |FROM
		                  |	Document.GoodsIssue AS GoodsIssue
		                  |WHERE
		                  |	GoodsIssue.ParentSalesOrder = &Ref");
		Query.SetParameter("Ref", FillingData.Ref);
		QueryResult = Query.Execute();
		If NOT QueryResult.IsEmpty() Then
			Message = New UserMessage();
			Message.Text=NStr("en='Goods Issues are created based on this Sales Order. Create Sales Invoices based on Goods Issues.'");
			Message.Message();
			DontCreate = True;
			Return;
		EndIf;
		
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
	
	If TypeOf(FillingData) = Type("DocumentRef.GoodsIssue") Then
		Company = FillingData.Company;
		DocumentTotal = FillingData.DocumentTotal;
		DocumentTotalRC = FillingData.DocumentTotalRC;
		ParentSalesOrder = FillingData.ParentSalesOrder;
		SalesTax = FillingData.SalesTax;
		Currency = FillingData.Currency;
		ExchangeRate = FillingData.ExchangeRate;
		Location = FillingData.Location;
		ParentGoodsIssue = FillingData.Ref;
		VATTotal = FillingData.VATTotal;
		ARAccount = FillingData.ARAccount;
		
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




