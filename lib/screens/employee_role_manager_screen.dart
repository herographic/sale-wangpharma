// lib/screens/employee_role_manager_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:salewang/models/customer.dart';
import 'package:salewang/models/daily_sales_status.dart'; // Assuming EmployeePayload is here
import 'package:http/http.dart' as http;

class EmployeeRoleManagerScreen extends StatefulWidget {
  const EmployeeRoleManagerScreen({super.key});

  @override
  State<EmployeeRoleManagerScreen> createState() =>
      _EmployeeRoleManagerScreenState();
}

class _EmployeeRoleManagerScreenState extends State<EmployeeRoleManagerScreen> {
  List<EmployeePayload> _allEmployees = [];
  Map<String, String> _employeeRoles = {};
  bool _isLoading = true;

  // NEW: State variables for sales stats
  Map<String, int> _salespersonTotalCustomers = {};
  final Map<String, int> _salespersonTodayCalls = {};
  final Map<String, int> _salespersonCalledCustomers = {};
  final Map<String, String> _uidToEmpCodeMap = {}; // Maps Firebase Auth UID to Employee Code

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      // 1. Fetch all employees from the API
      const String apiUrl = 'https://www.wangpharma.com/API/sale/day-status.php';
      const String token =
          'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJtZW1fY29kZSI6IjAzNTAifQ.9xQokBCn6ED-xwHQFXsa5Bah57dNc8vWJ_4Iin8E3m0';
      final response = await http.get(
        Uri.parse(apiUrl),
        headers: {'Authorization': 'Bearer $token'},
      );

      List<EmployeePayload> employees = [];
      if (response.statusCode == 200) {
        final List<DailySalesStatus> salesStatusList =
            dailySalesStatusFromJson(response.body);
        if (salesStatusList.isNotEmpty) {
          employees = salesStatusList.first.payload;
        }
      } else {
        throw Exception('Failed to load employee data from API');
      }

      // 2. Fetch current roles from Firestore
      final rolesSnapshot =
          await FirebaseFirestore.instance.collection('employee_roles').get();
      final rolesMap = {
        for (var doc in rolesSnapshot.docs) doc.id: doc.data()['role'] as String
      };

      // 3. Fetch salesperson UID to Employee Code mapping
      final salespeopleSnapshot = await FirebaseFirestore.instance.collection('salespeople').get();
      for (var doc in salespeopleSnapshot.docs) {
          final data = doc.data();
          if (data.containsKey('employeeId')) {
              _uidToEmpCodeMap[doc.id] = data['employeeId'];
          }
      }

      // 4. Fetch all customers and aggregate counts per salesperson
      final customersSnapshot = await FirebaseFirestore.instance.collection('customers').get();
      final tempCustomerCounts = <String, int>{};
      for (var doc in customersSnapshot.docs) {
          final customer = Customer.fromFirestore(doc);
          final salespersonCode = customer.salesperson;
          if (salespersonCode.isNotEmpty) {
              tempCustomerCounts[salespersonCode] = (tempCustomerCounts[salespersonCode] ?? 0) + 1;
          }
      }
      _salespersonTotalCustomers = tempCustomerCounts;

      // 5. Fetch today's call logs and aggregate counts
      final now = DateTime.now();
      final startOfToday = Timestamp.fromDate(DateTime(now.year, now.month, now.day));
      final callsSnapshot = await FirebaseFirestore.instance
          .collection('call_logs')
          .where('callTimestamp', isGreaterThanOrEqualTo: startOfToday)
          .get();

      final tempTodayCalls = <String, int>{}; // Keyed by UID
      final tempCalledCustomers = <String, Set<String>>{}; // Keyed by UID

      for (var doc in callsSnapshot.docs) {
          final data = doc.data();
          final uid = data['salespersonId'] as String?;
          final customerId = data['customerId'] as String?;
          if (uid != null && customerId != null) {
              tempTodayCalls[uid] = (tempTodayCalls[uid] ?? 0) + 1;
              tempCalledCustomers.putIfAbsent(uid, () => {}).add(customerId);
          }
      }

      // 6. Convert call stats from UID-keyed to EmployeeCode-keyed maps
      _salespersonTodayCalls.clear();
      _salespersonCalledCustomers.clear();
      tempTodayCalls.forEach((uid, count) {
          final empCode = _uidToEmpCodeMap[uid];
          if (empCode != null) {
              _salespersonTodayCalls[empCode] = count;
          }
      });
      tempCalledCustomers.forEach((uid, customerSet) {
          final empCode = _uidToEmpCodeMap[uid];
          if (empCode != null) {
              _salespersonCalledCustomers[empCode] = customerSet.length;
          }
      });


      if (mounted) {
        setState(() {
          _allEmployees = employees;
          _employeeRoles = rolesMap;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error fetching data: $e')),
        );
      }
    }
  }

  Future<void> _updateRole(String empCode, String newRole) async {
    try {
      await FirebaseFirestore.instance
          .collection('employee_roles')
          .doc(empCode)
          .set({'role': newRole});
      setState(() {
        _employeeRoles[empCode] = newRole;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('อัปเดตตำแหน่งสำเร็จ'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating role: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0052D4), Color(0xFF4364F7), Color(0xFF6FB1FC)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('จัดการตำแหน่งพนักงาน', style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Colors.white))
            : ListView.builder(
                padding: const EdgeInsets.all(8.0),
                itemCount: _allEmployees.length,
                itemBuilder: (context, index) {
                  final employee = _allEmployees[index];
                  final currentRole =
                      _employeeRoles[employee.empCode] ?? 'unassigned';
                  
                  // NEW: Get stats for this employee
                  final totalCalls = _salespersonTodayCalls[employee.empCode] ?? 0;
                  final totalCustomers = _salespersonTotalCustomers[employee.empCode] ?? 0;
                  final calledCustomers = _salespersonCalledCustomers[employee.empCode] ?? 0;

                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: Column( // Wrapped in a Column to add the new stats row
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 24,
                                backgroundImage: NetworkImage(employee.empImg),
                                onBackgroundImageError: (e, s) {}, // Handle image load error
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      employee.empNickname ?? employee.empCode,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                    ),
                                    Text('รหัส: ${employee.empCode}', style: TextStyle(color: Colors.grey.shade600)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              DropdownButton<String>(
                                value: currentRole,
                                underline: Container(), // Remove underline
                                items: const [
                                  DropdownMenuItem(
                                      value: 'unassigned', child: Text('ไม่ได้กำหนด')),
                                  DropdownMenuItem(value: 'sales', child: Text('ฝ่ายขาย')),
                                  DropdownMenuItem(
                                      value: 'data_entry', child: Text('ฝ่ายคีย์ข้อมูล')),
                                ],
                                onChanged: (String? newValue) {
                                  if (newValue != null) {
                                    _updateRole(employee.empCode, newValue);
                                  }
                                },
                              ),
                            ],
                          ),
                          // NEW: Conditional stats row for salespeople
                          if (currentRole == 'sales')
                            const Divider(height: 16, thickness: 0.5),
                          if (currentRole == 'sales')
                            Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceAround,
                                children: [
                                  _buildStatChip(Icons.phone_in_talk_outlined, 'โทรวันนี้', '$totalCalls สาย'),
                                  _buildStatChip(Icons.people_alt_outlined, 'ลูกค้า', '$calledCustomers/$totalCustomers ร้าน'),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  // NEW: Helper widget to display a single stat
  Widget _buildStatChip(IconData icon, String label, String value) {
    return Column(
        children: [
            Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
            const SizedBox(height: 2),
            Row(
                children: [
                    Icon(icon, size: 14, color: Theme.of(context).primaryColor),
                    const SizedBox(width: 4),
                    Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ],
            ),
        ],
    );
  }
}
