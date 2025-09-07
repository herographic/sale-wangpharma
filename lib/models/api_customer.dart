// lib/models/api_customer.dart

import 'dart:convert';

// Helper function to parse a JSON string into a List of ApiCustomer objects.
// This function is robust and can handle single objects or lists from the API.
List<ApiCustomer> apiCustomerFromJson(String str) {
  try {
    final jsonData = json.decode(str);
    if (jsonData is List) {
      return List<ApiCustomer>.from(jsonData.map((x) => ApiCustomer.fromJson(x)));
    } else if (jsonData is Map<String, dynamic>) {
      // Handle case where a single object is returned
      if (jsonData.containsKey('mem_code') && jsonData['mem_code'] != null) {
        return [ApiCustomer.fromJson(jsonData)];
      }
      return [];
    }
    return [];
  } catch (e) {
    // Return an empty list if there's a decoding error
    return [];
  }
}

// Main model for the customer data from the API, matching the provided JSON structure 100%.
class ApiCustomer {
    final String? memId;
    final String? memImg;
    final String? memCode;
    final String? memName;
    final String? memRoute;
    final String? memPrice;
    final String? memLimit;
    final String? memPhone;
    final String? mnEmailshop;
    final String? mnLineadd;
    final String? mnWebsite;
    final String? mnFacebook;
    final String? memAddress;
    final String? memSgroup;
    final String? memUsername;
    final String? memPassword;
    final String? memTaxid;
    final String? memSuboffice;
    final String? memIncart;
    final String? memThisMount;
    final List<MemInvoice> memInvoice;
    final List<Top40Product> top40Product;
    final String? memFavorites;
    final List<dynamic> favorites;
    final List<MemSite> memSite;
    final String? memLogistic;
    final String? memDatecontact;
    final String? empSale;
    final String? memBearer;
    final String? telesale;
    final String? empTelesale;
    final String? memLastsale;

    ApiCustomer({
        this.memId,
        this.memImg,
        this.memCode,
        this.memName,
        this.memRoute,
        this.memPrice,
        this.memLimit,
        this.memPhone,
        this.mnEmailshop,
        this.mnLineadd,
        this.mnWebsite,
        this.mnFacebook,
        this.memAddress,
        this.memSgroup,
        this.memUsername,
        this.memPassword,
        this.memTaxid,
        this.memSuboffice,
        this.memIncart,
        this.memThisMount,
        required this.memInvoice,
        required this.top40Product,
        this.memFavorites,
        required this.favorites,
        required this.memSite,
        this.memLogistic,
        this.memDatecontact,
        this.empSale,
        this.memBearer,
        this.telesale,
        this.empTelesale,
        this.memLastsale,
    });

    factory ApiCustomer.fromJson(Map<String, dynamic> json) => ApiCustomer(
        memId: json["mem_id"],
        memImg: json["mem_img"],
        memCode: json["mem_code"],
        memName: json["mem_name"],
        memRoute: json["mem_route"],
        memPrice: json["mem_price"],
        memLimit: json["mem_limit"],
        memPhone: json["mem_phone"],
        mnEmailshop: json["mn_emailshop"],
        mnLineadd: json["mn_lineadd"],
        mnWebsite: json["mn_website"],
        mnFacebook: json["mn_facebook"],
        memAddress: json["mem_address"],
        memSgroup: json["mem_sgroup"],
        memUsername: json["mem_username"],
        memPassword: json["mem_password"],
        memTaxid: json["mem_taxid"],
        memSuboffice: json["mem_suboffice"],
        memIncart: json["mem_incart"],
        memThisMount: json["mem_thismount"],
        memInvoice: json["mem_invoice"] == null ? [] : List<MemInvoice>.from(json["mem_invoice"]!.map((x) => MemInvoice.fromJson(x))),
        top40Product: json["top_40product"] == null ? [] : List<Top40Product>.from(json["top_40product"]!.map((x) => Top40Product.fromJson(x))),
        memFavorites: json["mem_favorites"],
        favorites: json["favorites"] == null ? [] : List<dynamic>.from(json["favorites"]!.map((x) => x)),
        memSite: json["mem_site"] == null ? [] : List<MemSite>.from(json["mem_site"]!.map((x) => MemSite.fromJson(x))),
        memLogistic: json["mem_logistic"],
        memDatecontact: json["mem_datecontact"],
        empSale: json["emp_sale"],
        memBearer: json["mem_bearer"],
        telesale: json["telesale"],
        empTelesale: json["emp_telesale"],
        memLastsale: json["mem_lastsale"],
    );
}

class MemInvoice {
    final String? mvDate;
    final String? mvInvoice;
    final String? mvTotal;
    final String? mvPay;
    final String? mvBalance;

    MemInvoice({
        this.mvDate,
        this.mvInvoice,
        this.mvTotal,
        this.mvPay,
        this.mvBalance,
    });

    factory MemInvoice.fromJson(Map<String, dynamic> json) => MemInvoice(
        mvDate: json["mv_date"],
        mvInvoice: json["mv_invoice"],
        mvTotal: json["mv_total"],
        mvPay: json["mv_pay"],
        mvBalance: json["mv_balance"],
    );
}

class Top40Product {
    final String? proCode;
    final String? proName;
    final String? proPrice;

    Top40Product({
        this.proCode,
        this.proName,
        this.proPrice,
    });

    factory Top40Product.fromJson(Map<String, dynamic> json) => Top40Product(
        proCode: json["pro_code"],
        proName: json["pro_name"],
        proPrice: json["pro_price"],
    );
}

class MemSite {
    final bool? web;
    final bool? app;
    final bool? line;
    final bool? tel;
    final bool? other;
    final bool? mail;

    MemSite({
        this.web,
        this.app,
        this.line,
        this.tel,
        this.other,
        this.mail,
    });

    factory MemSite.fromJson(Map<String, dynamic> json) => MemSite(
        web: json["Web"],
        app: json["App"],
        line: json["Line"],
        tel: json["Tel"],
        other: json["Other"],
        mail: json["Mail"],
    );
}
