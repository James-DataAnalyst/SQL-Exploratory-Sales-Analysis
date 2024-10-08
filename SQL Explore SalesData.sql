USE [PORTFOLIO]
GO
/****** Object:  StoredProcedure [dbo].[Exploratory_sales_analysis]    Script Date: 9/7/2024 7:44:03 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- =============================================
-- Author:		Isaac James
-- Create date: 20240905
-- Description:	SQL Exploratory Analysis for Sales Data 
-- =============================================

ALTER PROC [dbo].[Exploratory_sales_analysis]

AS
BEGIN

-- -------------------------------------------------
-- 1.DATA INSPECTION
-- -------------------------------------------------
SELECT *
FROM [dbo].[WRK_sales_data_sample]

-- -------------------------------------------------
-- 2. CHECKING UNIQUE VALUES
-- -------------------------------------------------
---This query investigate the distinct/unique vales for the selected fields
SELECT DISTINCT [STATUS] FROM [dbo].[WRK_sales_data_sample] --nice to plot
SELECT DISTINCT [YEAR_ID] FROM [dbo].[WRK_sales_data_sample]
SELECT DISTINCT [PRODUCTLINE] FROM [dbo].[WRK_sales_data_sample] --nice to plot
SELECT DISTINCT [COUNTRY] FROM [dbo].[WRK_sales_data_sample] --nice to plot
SELECT DISTINCT [DEALSIZE] FROM [dbo].[WRK_sales_data_sample] --nice to plot

---------------------------------------------------------------------
---3. ANALYSIS
---a. Let start by grouping SALES by PRODUCTLINE, YEAR_ID, & DEALSIZE
---------------------------------------------------------------------
SELECT [PRODUCTLINE], SUM([SALES]) REVENUE
FROM [dbo].[WRK_sales_data_sample]
GROUP BY [PRODUCTLINE]
ORDER BY 2 DESC

SELECT [YEAR_ID], SUM([SALES]) REVENUE
FROM [dbo].[WRK_sales_data_sample]
GROUP BY [YEAR_ID]
ORDER BY 2 DESC

SELECT [DEALSIZE], SUM([SALES]) REVENUE
FROM [dbo].[WRK_sales_data_sample]
GROUP BY [DEALSIZE]
ORDER BY 2 DESC
---Classic Cars, 2004 and Medium size return the highest revenue

---------------------------------------------------
-- b. Best Month for Sales
---------------------------------------------------
---What was the best month for sales in a specific year? how much was earned that month?
-- This query finds the best month for sales in the year 2003 by summing the sales for each month and ordering the result by total sales.

SELECT [MONTH_ID], SUM([SALES]) REVENUE, COUNT([ORDERNUMBER]) FREQUENCY
FROM [dbo].[WRK_sales_data_sample]
WHERE [YEAR_ID] = 2003 --- Change date to see the rest
GROUP BY [MONTH_ID]
ORDER BY 2 DESC 

---November seems to be the month, what product do they sell most in November? Classic I believe
SELECT [MONTH_ID], [PRODUCTLINE],  SUM([SALES]) REVENUE, COUNT([ORDERNUMBER]) FREQUENCY
FROM [dbo].[WRK_sales_data_sample]
WHERE [YEAR_ID] = 2003 AND [MONTH_ID] = 11 --- Change date to see the rest
GROUP BY [MONTH_ID], [PRODUCTLINE]
ORDER BY 3 DESC

---------------------------------------------------
-- C. RFM Analysis for	CUSTOMER SEGMENTATION
---------------------------------------------------
---Who is our best customer? (this will be best answered with RFM)
-- This query calculates Recency, Frequency, and Monetary value for each customer to perform RFM analysis.

DROP TABLE IF EXISTS #rfm 
;with rfm as
(
SELECT
   [CUSTOMERNAME],
   SUM([SALES]) MonetaryValue,
   AVG([SALES]) AvgMonetaryValue,
   COUNT([ORDERNUMBER]) Frequency,
   MAX([ORDERDATE]) Last_Order_Date,
   (SELECT  MAX ([ORDERDATE])  FROM [dbo].[WRK_sales_data_sample]) Max_Order_Date, 
  DATEDIFF (DD, MAX ([ORDERDATE]), (SELECT  MAX([ORDERDATE])  FROM [dbo].[WRK_sales_data_sample])) Recency
   FROM [dbo].[WRK_sales_data_sample]
   GROUP BY [CUSTOMERNAME]
   ),
   rfm_calc as
   (

   select r.*,
   NTILE (4) OVER (order by Recency desc) rfm_recency,
   NTILE (4) OVER (order by Frequency) rfm_frequency,
   NTILE (4) OVER (order by MonetaryValue) rfm_monetary   
   from rfm r

   )
   select c.*, rfm_recency+ rfm_frequency+ rfm_monetary as rfm_cell,
  cast (rfm_recency as varchar)+ cast (rfm_frequency as varchar) + cast (rfm_monetary as varchar) rfm_cell_string
  into #rfm
   from rfm_calc c

   select CUSTOMERNAME, rfm_recency, rfm_frequency, rfm_monetary, 
case
   when rfm_cell_string in (111, 112, 121, 123, 132, 211, 212, 114, 141, 122) then 'lost_customers' ---lost customers
   when rfm_cell_string in (133, 134, 143, 244, 334, 343, 344, 144, 234) then 'slipping away, cannot lose' ---(Big spenders who haven't purchased lately) slipping away
   when rfm_cell_string in (311, 411, 331, 421) then 'new customers' 
   when rfm_cell_string in (222, 223, 233, 322, 232, 221) then 'potentail churners'
   when rfm_cell_string in (323, 333, 321, 422, 332, 432, 412) then 'active'  ---(Customers who buy often & recently, but at low price points) slipping away
   when rfm_cell_string in (433, 434, 443, 444, 423) then 'loyal' 
end rfm_segment
   from #rfm;
  
------------------------------------------
---d. Churn Prediction 
------------------------------------------
---This query detect Customers Who Stopped Ordering__confirming lost customers from rfm analysis
WITH RecentOrders AS (
    SELECT CUSTOMERNAME, MAX(ORDERDATE) AS LastOrderDate
    FROM [dbo].[WRK_sales_data_sample]
    GROUP BY CUSTOMERNAME
),
OverallMaxDate AS (
    SELECT MAX(ORDERDATE) AS MaxOrderDate
    FROM [dbo].[WRK_sales_data_sample]
)
SELECT ro.CUSTOMERNAME, ro.LastOrderDate
FROM RecentOrders ro
CROSS JOIN OverallMaxDate omd
WHERE DATEDIFF(DAY, ro.LastOrderDate, omd.MaxOrderDate) > 365
ORDER BY ro.LastOrderDate DESC;

--------------------------------------------
---e. Customer Lifetime Value (CLV) Analysis 
--------------------------------------------
---This query calculate the total revenue generated by each customer over their lifetime with the company
---and ranked them in three value level (low, medium and high).
WITH CustomerRevenue AS (
    SELECT CUSTOMERNAME, SUM(SALES) AS TotalSales
    FROM [dbo].[WRK_sales_data_sample]
    GROUP BY CUSTOMERNAME
),
CustomerOrders AS (
    SELECT CUSTOMERNAME, COUNT(DISTINCT ORDERNUMBER) AS TotalOrders
    FROM [dbo].[WRK_sales_data_sample]
    GROUP BY CUSTOMERNAME
),
CustomerStats AS (
    SELECT c.CUSTOMERNAME, c.TotalSales, o.TotalOrders,
           (c.TotalSales / o.TotalOrders) AS AverageOrderValue
    FROM CustomerRevenue c
    JOIN CustomerOrders o
    ON c.CUSTOMERNAME = o.CUSTOMERNAME
),
RankedCustomers AS (
    SELECT CUSTOMERNAME, TotalSales, TotalOrders, AverageOrderValue,
           RANK() OVER (ORDER BY TotalSales DESC) AS SalesRank,
           CASE
               WHEN AverageOrderValue >= 50000 THEN 'High Value' -- Top 20%
               WHEN AverageOrderValue >= 25000 THEN 'Medium Value' -- Middle 60%
               ELSE 'Low Value' -- Bottom 20%
           END AS Remark
    FROM CustomerStats
)
SELECT CUSTOMERNAME, TotalSales, TotalOrders, AverageOrderValue, SalesRank, Remark
FROM RankedCustomers
ORDER BY SalesRank;

------------------------------------------
---f. Customer Segmentation by Deal Size
------------------------------------------
---This query segment customers based on the size of the deals (Small, Medium, Large)
---We can use the following query to find out which customers frequently make large purchases.
WITH DealSizeCounts AS (
    SELECT CUSTOMERNAME, DEALSIZE, COUNT(*) AS DealCount
    FROM [dbo].[WRK_sales_data_sample]
    GROUP BY CUSTOMERNAME, DEALSIZE
),
PivotedDealSizes AS (
    SELECT CUSTOMERNAME,
           ISNULL([Small], 0) AS SmallDealCount,
           ISNULL([Medium], 0) AS MediumDealCount,
           ISNULL([Large], 0) AS LargeDealCount
    FROM DealSizeCounts
    PIVOT (
        SUM(DealCount)
        FOR DEALSIZE IN ([Small], [Medium], [Large])
    ) AS PivotTable
)
SELECT CUSTOMERNAME, SmallDealCount, MediumDealCount, LargeDealCount
FROM PivotedDealSizes
ORDER BY SmallDealCount DESC, MediumDealCount DESC, LargeDealCount DESC;

-- -------------------------------------------------
-- g. Products Most Often Sold Together
-- -------------------------------------------------
---What products are most often sold together?
---This query identifies products that are often sold together by using a subquery to find orders with exactly two items.

---select * from [dbo].[WRK_sales_data_sample] where ORDERNUMBER = 10411
select distinct ORDERNUMBER, stuff (

   (select ','+ PRODUCTCODE
   from [dbo].[WRK_sales_data_sample] P
   where ORDERNUMBER in
   (
   select ORDERNUMBER
   from (

   select ORDERNUMBER, count (*) rn
   from [dbo].[WRK_sales_data_sample]
   where STATUS =  'Shipped'
   group by ORDERNUMBER
   ) m
   where rn =2 
   and p.ORDERNUMBER = s.ORDERNUMBER
   )
   for xml path (''))
   , 1, 1, '') PRODUCTCODES
   from [dbo].[WRK_sales_data_sample] s
   order by 2 desc;
   
-- -------------------------------------------------
-- h. Product Sales Trend Over Time
-- -------------------------------------------------
---This query examines sales trends over months, rank and filters the top 3 selling products per month 
WITH MonthlySales AS (
    SELECT YEAR_ID, MONTH_ID, PRODUCTCODE, SUM(SALES) AS TotalSales
    FROM [dbo].[WRK_sales_data_sample]
    GROUP BY YEAR_ID, MONTH_ID, PRODUCTCODE
),
RankedSales AS (
    SELECT YEAR_ID, MONTH_ID, PRODUCTCODE, TotalSales,
    RANK() OVER (PARTITION BY YEAR_ID ORDER BY TotalSales DESC) AS MonthlyRank
    FROM MonthlySales
)
SELECT YEAR_ID, MONTH_ID, PRODUCTCODE, TotalSales
FROM RankedSales
WHERE MonthlyRank <= 3
ORDER BY YEAR_ID, MONTH_ID, TotalSales DESC;


   END