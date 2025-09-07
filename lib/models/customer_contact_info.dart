// lib/models/customer_contact_info.dart
import 'dart:convert';

// Helper function to parse the JSON string into a list of CustomerContactInfo objects.
List<CustomerContactInfo> customerContactInfoFromJson(String str) {
    try {
        final jsonData = json.decode(str);
        if (jsonData is List) {
            return List<CustomerContactInfo>.from(jsonData.map((x) => CustomerContactInfo.fromJson(x)));
        }
        return [];
    } catch (e) {
        print('Error decoding CustomerContactInfo JSON: $e');
        return [];
    }
}

// Main model for the entire contact info object from the API.
class CustomerContactInfo {
    final String memCode;
    final String memName;
    final List<Officer> officer;
    final Telephone telephone;

    CustomerContactInfo({
        required this.memCode,
        required this.memName,
        required this.officer,
        required this.telephone,
    });

    factory CustomerContactInfo.fromJson(Map<String, dynamic> json) => CustomerContactInfo(
        memCode: json["mem_code"] ?? '',
        memName: json["mem_name"] ?? '',
        officer: json["officer"] == null ? [] : List<Officer>.from(json["officer"].map((x) => Officer.fromJson(x))),
        telephone: Telephone.fromJson(json["telephone"] ?? {}),
    );
}

// Model for an individual officer/contact person.
class Officer {
    final String career;
    final String phone;
    final String name;
    final String nick;
    final String sex;
    final String birthday;

    Officer({
        required this.career,
        required this.phone,
        required this.name,
        required this.nick,
        required this.sex,
        required this.birthday,
    });

    factory Officer.fromJson(Map<String, dynamic> json) => Officer(
        career: json["career"] ?? '',
        phone: json["phone"] ?? '',
        name: json["name"] ?? '',
        nick: json["nick"] ?? '',
        sex: json["sex"] ?? '',
        birthday: json["birthday"] ?? '',
    );
}

// Model for the shop's telephone numbers.
class Telephone {
    final String phone1;
    final String phone1Job;
    final String phone1Name;
    final String phone2;
    final String phone2Job;
    final String phone2Name;
    final String phone3;
    final String phone3Job;
    final String phone3Name;
    final String phone4;
    final String phone4Job;
    final String phone4Name;

    Telephone({
        required this.phone1,
        required this.phone1Job,
        required this.phone1Name,
        required this.phone2,
        required this.phone2Job,
        required this.phone2Name,
        required this.phone3,
        required this.phone3Job,
        required this.phone3Name,
        required this.phone4,
        required this.phone4Job,
        required this.phone4Name,
    });

    factory Telephone.fromJson(Map<String, dynamic> json) => Telephone(
        phone1: json["phone_1"] ?? '',
        phone1Job: json["phone_1_job"] ?? '',
        phone1Name: json["phone_1_name"] ?? '',
        phone2: json["phone_2"] ?? '',
        phone2Job: json["phone_2_job"] ?? '',
        phone2Name: json["phone_2_name"] ?? '',
        phone3: json["phone_3"] ?? '',
        phone3Job: json["phone_3_job"] ?? '',
        phone3Name: json["phone_3_name"] ?? '',
        phone4: json["phone_4"] ?? '',
        phone4Job: json["phone_4_job"] ?? '',
        phone4Name: json["phone_4_name"] ?? '',
    );
}
