import sys
import re

# Verify the user supplied an argument (6 digit employee ID).
if len(sys.argv) == 1:
	sys.exit("Please provide a 6 digit employee ID. (ex. >script.py 123456")
else:
	emp_id = sys.argv[1]

if not re.match(r'\A\d{6}\Z',emp_id):
	sys.exit("The employee ID must be 6 digits. (ex. >script.py 123456)")


employee_data = {}
employee_ids = {}
role_allocations = {}
verify_status = 0
total_cost = 0


def get_allocation(id_num): 
	global total_cost
	for employee_id in employee_ids:
		if employee_data[employee_id]['MANAGER'] == id_num:
			# If a role is not defined in allocations.cfg, hard stop!
			# Force user to edit cfg to define all roles, even if cost = 0. 
			if not role_allocations[employee_data[employee_id]['ROLE']]:
				sys.exit("[ERROR] Role: "
						+ str(employee_data[employee_id]['ROLE'])
						+ " not found. Add allocation to this role in "
						+ " allocations.cfg")
			# Add the allocation cost for employee's role to the global total.
			total_cost += role_allocations[employee_data[employee_id]['ROLE']]
			if employee_data[employee_id]['ROLE'] == "MANAGER":
				# Recursive loop, will be called each time a manager is found 
				# in the chain of command.
				get_allocation(employee_id)
				
def is_number(num):
	try:
		int(num)
		return True
	except ValueError:
		return False
		
				
				
# Load the allocation costs from cfg.
allocations = open('./allocations.cfg','r')
for line in allocations:
	line = line.rstrip('\n')
	# Ignores current line if no pipe is found. (ex. role|cost).
	if re.search(r'\|',line):
		(role,cost) = line.split('|')
		# Verify the cost is a number.
		if not is_number(cost):
			sys.exit("[ERROR] Cost in allocations.cfg must be a number. Role:" 
					+ role + " is currently configured to " + cost 
					+ " in allocations.cfg.")
		else:
			role_allocations[role.upper()] = int(cost)
allocations.close()


f = open('./employees.dat','r')
for line in f:
	line = line.rstrip('\n')
	(id,last,first,role,department,manager) = line.split('|')
	if id == emp_id:
		if role.upper() == "MANAGER":
			verify_status = 1
			total_cost+=300
		else:
			# If employee is not a manager, no need to move forward. 
			sys.exit(emp_id + ' is not a manager: ' + role)
	# Add data for each employee into a multidiminsional hash.
	# Some fields not currently used but are available for the future.
	employee_data[id] = {}
	employee_data[id]['LAST'] =  last
	employee_data[id]['FIRST'] =  first
	employee_data[id]['ROLE'] =  role.upper()
	employee_data[id]['DEPARTMENT'] =  department
	employee_data[id]['MANAGER'] =  manager

f.close()

# verify_status will remain 0 if emp_id was not found.
if not verify_status:
	sys.exit(emp_id + ' was not found')

# The employee_ids array (all emp_ids) is used in the get_allocation function.
employee_ids = employee_data.keys()
get_allocation(emp_id)

print("Total Allocation: " , total_cost)

		# if not re.match(r'^[0-9]+$',cost):




