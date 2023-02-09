/// REST services for managing the coffee business
Class ICO.Handler Extends %CSP.REST
{

/// Honor the CORS header <a href="https://docs.intersystems.com/irislatest/csp/docbook/DocBook.UI.Page.cls?KEY=GREST_CORS">as described here</a>
Parameter HandleCorsRequest = 1;

/// Default response content type
Parameter CONTENTTYPE = "application/json";

Parameter CONVERTINPUTSTREAM = 1;

Parameter CHARSET = "utf-8";

/// Number of days since roasting for the coffee to be considered "stale"
Parameter MAXAGE = 5;

/// Removes bags of coffee from the catalog
/// Input: <ul><li>id: catalog ID in catalog</li><li>quantity: number of bags to remove</li></ul>
/// Output: New product quantity on-hand, or an error
ClassMethod SellProduct(id As %String, quantity As %Numeric) As %Status
{
    try {
        // does the ID exist?
        if (1 '= ##class(ICO.catalog).%ExistsId(id))
        {
            set err = {}
            set err."error" = "Catalog ID "_id_" does NOT exist!"
            write err.%ToJSON()
        }
        else 
        {
            // do we have enough quantity?
            set item = ##class(ICO.catalog).%OpenId(id)
            if (quantity > item.quantity)
            {
                set err = {}
                set err."error" = "You tried to get "_quantity_" bags, but we only have "_item.quantity_" available."
                write err.%ToJSON()
            }
            else 
            {
                // decrement the database and return the new quantity
                set item.quantity = (item.quantity - quantity)
                do item.%JSONExportToString(.outstring)
                write outstring
                do item.%Save()
            }
        }
    } catch (oException) {
        // return the error
        set expobj = {}
        set expobj."exception" = oException.%AsSystemError()
        write expobj.%ToJSON()
    }
    Quit $$$OK
}

/// Gets  bagged coffee inventory for sale from the catalog
/// Input: fresh: if <pre>1</pre>, return stale bags (roasted more than <PARAMETER>MAXAGE</PARAMETER> days ago).
/// Output: JSON listing of products
ClassMethod GetProducts(fresh As %Boolean = 1) As %Status
{
    try {
        // fields to return
        set sqlquery = "SELECT catalog_id, product_code, quantity, price, time_roasted, roasting_notes, img FROM ICO.catalog"
        // set the WHERE clause based on whether we want fresh or not (the -? will be replaced by MAXAGE)
        if fresh = 1 {
            set sqlquery = sqlquery_" WHERE time_roasted > DATEADD('day',-?,CURRENT_DATE)"
        } else {
            set sqlquery = sqlquery_" WHERE time_roasted <= DATEADD('day',-?,CURRENT_DATE)"
        }
        // if nothing is left, exclude from the response
        set sqlquery = sqlquery_" AND quantity > 0"
        // run the query
        set rs = ##class(%SQL.Statement).%ExecDirect(,sqlquery, ..#MAXAGE)
        set itemsarray = []

        // iterate over the results and build a dynamic array
        while rs.%Next()
        {
            do itemsarray.%Push(
                {
                    "catalog_id": (rs.%Get("catalog_id")),
                    "product_code": (rs.%Get("product_code")), 
                    "quantity": (rs.%Get("quantity")),
                    "time_roasted": (rs.%Get("time_roasted")),
                    "roasting_notes": (rs.%Get("roasting_notes")),
                    "img": (rs.%Get("img")),
                    "price": (rs.%Get("price"))
                }
            )
        }
        // translate the dynamic arry into JSON and return to client
        set itemsobj = {}
        set itemsobj."rowcount" = rs.%ROWCOUNT
        set itemsobj."products" = itemsarray
        write itemsobj.%ToJSON()
    } catch (oException) {
        set expobj = {}
        set expobj."exception" = oException
        write expobj.%ToJSON()
    }
    Quit $$$OK
}

/// Create JSON from POST content
ClassMethod GetJSONFromRequest(Output obj As %DynamicObject) As %Boolean
{
    set ok = 1
    try {
        set obj = ##class(%DynamicObject).%FromJSON(%request.Content)
    } catch ex {
        set ok = 0
    }
    Quit ok
}

/// Accepts JSON in an HTTP POST and persists it into the bagged coffee catalog
/// Input: None explicit. Will get HTTP POST content when calling <METHOD>GetJSONFromRequest</METHOD>
/// Output: on success, JSON having a key/value of "success": 1, and the object saved, or an error.
ClassMethod CatalogProduct() As %Status
{
    // get HTTP POST content
    if '..GetJSONFromRequest(.obj) {
        set %response.Status = ..#HTTP400BADREQUEST
        set error = {"error": "No JSON body in request"}
        write error.%ToJSON()
        Quit $$$OK
    }

    /// construct a new ICO.catalog object and populate it from the input
    try {
        set catobj = ##class(ICO.catalog).%New()
        set catobj.productcode = obj."product_code"
        set catobj.quantity = obj."quantity"
        set catobj.price = obj."price"
        set catobj.timeroasted = obj."time_roasted"
        set catobj.roastingnotes = obj."roasting_notes"
        set catobj.img = obj."img"
        do catobj.%Save()
        set resp = {}
        set resp."success" = 1
        write resp.%ToJSON()
    } catch (oException) {
        set expobj = {}
        set expobj."exception" = oException.%AsSystemError()
        set %response.Status = ..#HTTP400BADREQUEST
        write expobj.%ToJSON()
    }
    Quit $$$OK
}

/// Takes raw coffee beans out of inventory so they can be virtually roasted
/// Input: <ul><li>id: vendor id in catalog</li><li>quantity: amount in kilograms</li></ul>
/// Output: on success, JSON of the item and quantity withdrawn, or an error.
ClassMethod GetRawBeans(id As %String, quantity As %Numeric) As %Status
{
    try {
        // does the vendor ID exist?
        if (1 '= ##class(ICO.inventory).%ExistsId(id))
        {
            set err = {}
            set err."error" = "ID "_id_" does NOT exist!"
            write err.%ToJSON()
        }
        else 
        {
            // do we have enough quantity?
            set item = ##class(ICO.inventory).%OpenId(id)
            if (quantity > item.quantitykg)
            {
                set err = {}
                set err."error" = "You tried to get "_quantity_", but we only have "_item.quantitykg_" kilograms available."
                write err.%ToJSON()
            }
            else 
            {
                // decrement the quantity and return the requested inventory
                set item.quantitykg = (item.quantitykg - quantity)
                do item.%Save()
                do item.%JSONExportToString(.outstring)
                write outstring
            }
        }
    } catch (oException) {
        set expobj = {}
        set expobj."exception" = oException.%AsSystemError()
        write expobj.%ToJSON()
    }
    Quit $$$OK
}

/// Return raw coffee bean inventory
/// Input: None
/// Output: on success, JSON listing all products on hand, or an error.
ClassMethod ListRawBeans() As %Status
{
    try {
        set sqlquery = "SELECT ID, vendor_product_code, date_arrival, SUM(quantity_kg) AS quantity_kg FROM ICO.inventory GROUP BY vendor_product_code ORDER BY date_arrival"
        set rs = ##class(%SQL.Statement).%ExecDirect(,sqlquery)
        set itemsarray = []

        while rs.%Next()
        {
            do itemsarray.%Push(
                {
                    "id": (rs.%Get("ID")),
                    "vendor_product_code": (rs.%Get("vendor_product_code")), 
                    "date_arrival": (rs.%Get("date_arrival")), 
                    "quantity_kg": (rs.%Get("quantity_kg"))
                }
            )
        }
        set itemsobj = {}
        set itemsobj."rowcount" = rs.%ROWCOUNT
        set itemsobj."items" = itemsarray
        write itemsobj.%ToJSON()
    } catch (oException) {
        set expobj = {}
        set expobj."exception" = oException
        write expobj.%ToJSON()
    }
    Quit $$$OK
}

XData UrlMap [ XMLNamespace = "http://www.intersystems.com/urlmap" ]
{
<Routes>
    <Route Url="/inventory/listbeans" Method="GET" Call="ListRawBeans" />
    <Route Url="/inventory/getbeans/:id/:quantity" Method="POST" Call="GetRawBeans" />
    <Route Url="/catalog/catalogproduct" Method="POST" Call="CatalogProduct" />
    <Route Url="/catalog/getproducts" Method="GET" Call="GetProducts" /> 
    <Route Url="/catalog/getproducts/:fresh" Method="GET" Call="GetProducts" />
    <Route Url="/catalog/sellproduct/:id/:quantity" Method="POST" Call="SellProduct" />
</Routes>
}

}
