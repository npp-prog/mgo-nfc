import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_scope.dart';
import '../../models/app_user.dart';
import '../../router.dart';

class EmployeesScreen extends StatefulWidget {
  const EmployeesScreen({super.key});

  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen> {
  String _query = '';
  bool _showInactive = false;

  bool _matches(AppUser u) {
    if (!_showInactive && !u.active) return false;
    final q = _query.trim().toLowerCase();
    return q.isEmpty ||
        u.name.toLowerCase().contains(q) ||
        u.email.toLowerCase().contains(q) ||
        u.employeeId.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final admin = AppScope.of(context).admin;
    return Scaffold(
      appBar: AppBar(title: const Text('Employees')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.employeeNew),
        icon: const Icon(Icons.person_add),
        label: const Text('Add'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              key: const Key('employee-search'),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search name, email or ID',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          SwitchListTile(
            title: const Text('Show deactivated'),
            value: _showInactive,
            onChanged: (v) => setState(() => _showInactive = v),
          ),
          Expanded(
            child: StreamBuilder<List<AppUser>>(
              stream: admin.watchUsers(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return const Center(child: Text('Could not load employees.'));
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final users = snap.data!.where(_matches).toList();
                if (users.isEmpty) {
                  return const Center(child: Text('No employees found.'));
                }
                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: users.length,
                  itemBuilder: (context, i) {
                    final u = users[i];
                    return ListTile(
                      key: Key('employee-${u.uid}'),
                      leading: CircleAvatar(
                        child: Text(
                          u.name.isEmpty ? '?' : u.name[0].toUpperCase(),
                        ),
                      ),
                      title: Text(u.name),
                      subtitle: Text(
                        [
                          u.employeeId,
                          u.email,
                          if (u.isAdmin) 'Admin',
                          if (!u.trackAttendance) 'Not tracked',
                          if (!u.active) 'Deactivated',
                        ].join(' · '),
                      ),
                      enabled: u.active,
                      onTap: () => context.push(Routes.employeeEdit(u.uid)),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
