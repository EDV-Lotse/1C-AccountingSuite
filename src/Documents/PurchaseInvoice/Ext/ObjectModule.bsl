﻿
////////////////////////////////////////////////////////////////////////////////
// Purchase Invoice: Object module
//------------------------------------------------------------------------------

////////////////////////////////////////////////////////////////////////////////
// OBJECT EVENTS HANDLERS

Procedure BeforeWrite(Cancel, WriteMode, PostingMode)
	
	// Save document parameters before posting the document
	If WriteMode = DocumentWriteMode.Posting
	Or WriteMode = DocumentWriteMode.UndoPosting Then
	
		// Save custom document parameters
		Orders = LineItems.UnloadColumn("Order");
		GeneralFunctions.NormalizeArray(Orders);
		
		// Common filling of parameters
		DocumentParameters = New Structure("Ref, Date, IsNew,   Posted, ManualAdjustment, Metadata,   Orders",
		                                    Ref, Date, IsNew(), Posted, ManualAdjustment, Metadata(), Orders);
		DocumentPosting.PrepareDataStructuresBeforeWrite(AdditionalProperties, DocumentParameters, Cancel, WriteMode, PostingMode);
	EndIf;
		
	// Prcheck of register balances to complete filling of document posting
	If WriteMode = DocumentWriteMode.Posting Then
		
		// Precheck of document data, calculation of temporary data, required for document posting
		If (Not ManualAdjustment) And (Orders.Count() > 0) Then
			DocumentParameters = New Structure("Ref, PointInTime,   Company, LineItems",
			                                    Ref, PointInTime(), Company, LineItems.Unload(, "Order, Product, Quantity"));
			Documents.PurchaseInvoice.PrepareDataBeforeWrite(AdditionalProperties, DocumentParameters, Cancel);
		EndIf;
		
	EndIf;
	
EndProcedure

Procedure Posting(Cancel, PostingMode)
	
	// 1. Common postings clearing / reactivate manual ajusted postings
	DocumentPosting.PrepareRecordSetsForPosting(AdditionalProperties, RegisterRecords);
	
	// 2. Skip manually adjusted documents
	If ManualAdjustment Then
		Return;
	EndIf;

	// 3. Create structures with document data to pass it on the server
	DocumentPosting.PrepareDataStructuresBeforePosting(AdditionalProperties);
	
	// 4. Collect document data, available for posing, and fill created structure 
	Documents.PurchaseInvoice.PrepareDataStructuresForPosting(Ref, AdditionalProperties, RegisterRecords);

	// 5. Fill register records with document's postings
	DocumentPosting.FillRecordSets(AdditionalProperties, RegisterRecords, Cancel);

	// 6. Write document postings to register
	DocumentPosting.WriteRecordSets(AdditionalProperties, RegisterRecords);

	// 7. Check register blanaces according to document's changes
	DocumentPosting.CheckPostingResults(AdditionalProperties, RegisterRecords, Cancel);

	// 8. Clear used temporary document data
	DocumentPosting.ClearDataStructuresAfterPosting(AdditionalProperties);
	
	
	// OLD Posting
	
	RegisterInventory = True;
	
	If BegBal Then
				
		Reg = AccountingRegisters.GeneralJournal.CreateRecordSet();
		Reg.Filter.Recorder.Set(Ref);
		Reg.Clear();
		RegLine = Reg.AddCredit();
		RegLine.Account = APAccount;
		RegLine.Period = Date;
		If GetFunctionalOption("MultiCurrency") Then
			RegLine.Amount = DocumentTotal;
		Else
			RegLine.Amount = DocumentTotalRC;
		EndIf;
		RegLine.AmountRC = DocumentTotalRC;
		RegLine.Currency = Currency;
		RegLine.ExtDimensions[ChartsOfCharacteristicTypes.Dimensions.Company] = Company;
		RegLine.ExtDimensions[ChartsOfCharacteristicTypes.Dimensions.Document] = Ref;
		Reg.Write();
		
		Return;
		
	EndIf;
	
	If RegisterInventory Then
		
		RegisterRecords.InventoryJrnl.Write = True;
		
		For Each CurRowLineItems In LineItems Do
			If CurRowLineItems.Product.Type = Enums.InventoryTypes.Inventory Then
				Record = RegisterRecords.InventoryJrnl.Add();
				Record.RecordType = AccumulationRecordType.Receipt;
				Record.Period = Date;
				Record.Product = CurRowLineItems.Product;
				Record.Location = Location;
				If CurRowLineItems.Product.CostingMethod = Enums.InventoryCosting.WeightedAverage Then
				Else
					Record.Layer = Ref;
				EndIf;
				Record.Qty = CurRowLineItems.Quantity;				
				ItemAmount = 0;
				ItemAmount = CurRowLineItems.Quantity * CurRowLineItems.Price * ExchangeRate; 
				Record.Amount = ItemAmount;
				
				// Updating the ItemLastCost register
				Reg = InformationRegisters.ItemLastCost.CreateRecordManager();
				Reg.Product = CurRowLineItems.Product;
				Reg.Cost = ItemAmount / CurRowLineItems.Quantity;
				Reg.Write(True);
				
			EndIf;
		EndDo;
		
	EndIf;	
		
	// fill in the account posting value table with amounts
	
	PostingDatasetVAT = New ValueTable();
	PostingDatasetVAT.Columns.Add("VATAccount");
	PostingDatasetVAT.Columns.Add("AmountRC");
	
	PostingDataset = New ValueTable();
	PostingDataset.Columns.Add("Account");
	PostingDataset.Columns.Add("AmountRC");	
	
	CalculateByPlannedCosting = False;
	//PurchaseVarianceAccount = Constants.PurchaseVarianceAccount.Get();
	
	For Each CurRowLineItems in LineItems Do
		// Detect inventory item in table part
		IsInventoryPosting = (Not CurRowLineItems.Product.IsEmpty()) And (CurRowLineItems.Product.Type = Enums.InventoryTypes.Inventory);
		
		PostingLine = PostingDataset.Add();       
		If CalculateByPlannedCosting And IsInventoryPosting Then
			//PostingLine.Account = AccruedPurchasesAccount;
		Else
			PostingLine.Account = CurRowLineItems.Product.InventoryOrExpenseAccount;
		EndIf;	
		If PriceIncludesVAT Then
			PostingLine.AmountRC = (CurRowLineItems.LineTotal - CurRowLineItems.VAT) * ExchangeRate;
		Else
			PostingLine.AmountRC = CurRowLineItems.LineTotal * ExchangeRate;
		EndIf;
		
		// Calculating diference between ordered cost and invoiced cost of inventory items
		//If CalculateByPlannedCosting And IsInventoryPosting Then
		//	// Calculate difference in ordered and invoiced sum
		//	OrderCostDiff = CurRowLineItems.Quantity * (CurRowLineItems.OrderPrice - CurRowLineItems.Price);
		//	// Book found difference
		//	If OrderCostDiff <> 0 Then
		//		// Increase/Decrease booked value by ordering cost
		//		PostingLine.AmountRC = PostingLine.AmountRC + OrderCostDiff;
		//		// Found difference will be booked to the Purchased Variance account
		//		PostingLine = PostingDataset.Add();       
		//		PostingLine.Account = PurchaseVarianceAccount;
		//		PostingLine.AmountRC = - OrderCostDiff;
		//	EndIf;
		//EndIf;
		
		If CurRowLineItems.VAT > 0 Then
			PostingLineVAT = PostingDatasetVAT.Add();
			PostingLineVAT.VATAccount = VAT_FL.VATAccount(CurRowLineItems.VATCode, "Purchase");
			PostingLineVAT.AmountRC = CurRowLineItems.VAT * ExchangeRate;
		EndIf;
		
	EndDo;
	
	For Each CurRowAccount in Accounts Do
		PostingLine = PostingDataset.Add();
		PostingLine.Account = CurRowAccount.Account;
		PostingLine.AmountRC = CurRowAccount.Amount * ExchangeRate;
	EndDo;
	
	PostingDataset.GroupBy("Account", "AmountRC");
	
	NoOfPostingRows = PostingDataset.Count();
	
	// GL posting
	
	RegisterRecords.GeneralJournal.Write = True;	
	
	For i = 0 To NoOfPostingRows - 1 Do
		
		If PostingDataset[i][1] > 0 Then // Dr: Amount > 0
			Record = RegisterRecords.GeneralJournal.AddDebit();
			Record.Account = PostingDataset[i][0];
			Record.Period = Date;
			Record.AmountRC = PostingDataset[i][1];
			
		ElsIf PostingDataset[i][1] < 0 Then // Cr: Amount < 0
			Record = RegisterRecords.GeneralJournal.AddCredit();
			Record.Account = PostingDataset[i][0];
			Record.Period = Date;
			Record.AmountRC = -PostingDataset[i][1];
			
		EndIf;	
	EndDo;
	
	Record = RegisterRecords.GeneralJournal.AddCredit();
	Record.Account = APAccount;
	Record.Period = Date;
	Record.Amount = DocumentTotal;
	Record.Currency = Currency;
	Record.AmountRC = DocumentTotal * ExchangeRate;
	Record.ExtDimensions[ChartsOfCharacteristicTypes.Dimensions.Company] = Company;
	Record.ExtDimensions[ChartsOfCharacteristicTypes.Dimensions.Document] = Ref;
	
	PostingDatasetVAT.GroupBy("VATAccount", "AmountRC");
	NoOfPostingRows = PostingDatasetVAT.Count();
	For i = 0 To NoOfPostingRows - 1 Do
		Record = RegisterRecords.GeneralJournal.AddDebit();
		Record.Account = PostingDatasetVAT[i][0];
		Record.Period = Date;
		Record.AmountRC = PostingDatasetVAT[i][1];	
	EndDo;	
	 	 	
EndProcedure

Procedure UndoPosting(Cancel)

	// OLD Undo Posting
	
	If BegBal Then
		Return;
	EndIf;
	
	Query = New Query("SELECT
	                  |	PurchaseInvoiceLineItems.Product,
	                  |	SUM(PurchaseInvoiceLineItems.Quantity) AS Quantity
	                  |FROM
	                  |	Document.PurchaseInvoice.LineItems AS PurchaseInvoiceLineItems
	                  |WHERE
	                  |	PurchaseInvoiceLineItems.Ref = &Ref
	                  |	AND PurchaseInvoiceLineItems.Product.Type = VALUE(Enum.InventoryTypes.Inventory)
	                  |
	                  |GROUP BY
	                  |	PurchaseInvoiceLineItems.Product");
	Query.SetParameter("Ref", Ref);
	Dataset = Query.Execute().Choose();
	
	While Dataset.Next() Do
	
		CurrentBalance = 0;
		
		Query2 = New Query("SELECT
						  |	InventoryJrnlBalance.QtyBalance
						  |FROM
						  |	AccumulationRegister.InventoryJrnl.Balance AS InventoryJrnlBalance
						  |WHERE
						  |	InventoryJrnlBalance.Product = &Product
						  |	AND InventoryJrnlBalance.Location = &Location");			
		
		Query2.SetParameter("Product", Dataset.Product);
		Query2.SetParameter("Location", Location);
		
		QueryResult = Query2.Execute();
			
		If QueryResult.IsEmpty() Then
		Else
			Dataset2 = QueryResult.Unload();
			CurrentBalance = Dataset2[0][0];
		EndIf;
						
		If Dataset.Quantity > CurrentBalance Then
			Cancel = True;
			Message = New UserMessage();
			Message.Text=NStr("en='Insufficient balance';de='Nicht ausreichende Bilanz'");
			Message.Message();
			Return;
		EndIf;
		
	EndDo;	
	
	// 1. Common posting clearing / deactivate manual ajusted postings
	DocumentPosting.PrepareRecordSetsForPostingClearing(AdditionalProperties, RegisterRecords);
	
	// 2. Skip manually adjusted documents
	If ManualAdjustment Then
		Return;
	EndIf;
	
	// 3. Create structures with document data to pass it on the server
	DocumentPosting.PrepareDataStructuresBeforePosting(AdditionalProperties);
	
	// 4. Collect document data, required for posing clearing, and fill created structure 
	Documents.PurchaseInvoice.PrepareDataStructuresForPostingClearing(Ref, AdditionalProperties, RegisterRecords);
	
	// 5. Write document postings to register
	DocumentPosting.WriteRecordSets(AdditionalProperties, RegisterRecords);

	// 6. Check register blanaces according to document's changes
	DocumentPosting.CheckPostingResults(AdditionalProperties, RegisterRecords, Cancel);

	// 7. Clear used temporary document data
	DocumentPosting.ClearDataStructuresAfterPosting(AdditionalProperties);
	
EndProcedure

Procedure OnCopy(CopiedObject)
	
	// Clear manual ajustment attribute
	ManualAdjustment = False;
	
EndProcedure

Procedure Filling(FillingData, StandardProcessing)
	Var TabularSectionData; Cancel = False;
	
	// Filling on the base of other referenced object
	If FillingData <> Undefined Then
		
		// 0. Custom check of purchase order for interactive generate of purchase invoice on the base of purchase order
		If (TypeOf(FillingData) = Type("DocumentRef.PurchaseOrder"))
		And Not Documents.PurchaseInvoice.CheckStatusOfPurchaseOrder(FillingData) Then
			Cancel = True;
			Return;
		EndIf;		
		
		// 1. Common filling of parameters
		DocumentParameters = New Structure("Ref, Date, Metadata",
		                                    Ref, ?(ValueIsFilled(Date), Date, CurrentSessionDate()), Metadata());
		DocumentFilling.PrepareDataStructuresBeforeFilling(AdditionalProperties, DocumentParameters, FillingData, Cancel);
		
		// 2. Cancel filling on failed data
		If Cancel Then
			Return;
		EndIf;
			
		// 3. Collect document data, available for filling, and fill created structure 
		Documents.PurchaseInvoice.PrepareDataStructuresForFilling(Ref, AdditionalProperties);
			
		// 4. Check collected data
		DocumentFilling.CheckDataStructuresOnFilling(AdditionalProperties, Cancel);
		
		// 5. Fill document fields
		If Not Cancel Then
			// Fill "draft" values to attributes (all including non-critical fields will be filled)
			FillPropertyValues(ThisObject, AdditionalProperties.Filling.FillingTables.Table_Attributes[0]);
			
			// Fill checked unique values to attributes (critical fields will be filled)
			FillPropertyValues(ThisObject, AdditionalProperties.Filling.FillingTables.Table_Check[0]);
			
			// Fill line items
			For Each TabularSection In AdditionalProperties.Metadata.TabularSections Do
				If AdditionalProperties.Filling.FillingTables.Property("Table_" + TabularSection.Name, TabularSectionData) Then
					ThisObject[TabularSection.Name].Load(TabularSectionData);
				EndIf;
			EndDo;
		EndIf;
		
		// 6. Clear used temporary document data
		DocumentFilling.ClearDataStructuresAfterFilling(AdditionalProperties);
	EndIf;
	
EndProcedure

Procedure FillCheckProcessing(Cancel, CheckedAttributes)
	
	// Check doubles in items (to be sure of proper orders placement)
	GeneralFunctions.CheckDoubleItems(Ref, LineItems, "Order, Product, LineNumber", Cancel);
	
EndProcedure


