#!/bin/bash

DB="billing_db"
MYSQL="mysql -u root -pdeepanshi -D $DB -e"
clear

# Start Screen
banner BILLING
banner MANAGEMENT
banner SYSTEM
echo
echo "Press Q to Continue"
read -n1 input
echo
if [[ "$input" != "Q" && "$input" != "q" ]]; then
    echo "Invalid input. Exiting..."
    exit 1
fi
clear

# FUNCTIONS

add_customer(){
    name=$(dialog --inputbox "Enter customer name:" 10 40 3>&1 1>&2 2>&3 3>&-)
    while true; do
        contact=$(dialog --inputbox "Enter 10-digit contact number:" 10 40 3>&1 1>&2 2>&3 3>&-)
        if [[ "$contact" =~ ^[0-9]{10}$ ]]; then
            break
        else
            dialog --msgbox "Invalid contact number. Must be exactly 10 digits." 6 40
        fi
    done
    $MYSQL "INSERT INTO customers(name, contact) VALUES('$name', '$contact');"
    dialog --msgbox "Customer added successfully!" 6 40
}

delete_customer(){
    id=$(dialog --inputbox "Enter customer ID to delete:" 10 40 3>&1 1>&2 2>&3 3>&-)
    $MYSQL "DELETE FROM customers WHERE id=$id;"
    dialog --msgbox "Customer deleted (if not referenced by any bill)." 6 50
}

view_customer(){
    temp_file=$(mktemp)
    echo "ID   | Name                 | Contact" > "$temp_file"
    echo "-----|----------------------|--------------" >> "$temp_file"
    $MYSQL "SELECT id, name, contact FROM customers;" | tail -n +2 | awk '{ printf "%-4s | %-20s | %-10s\n", $1, $2, $3 }' >> "$temp_file"
    dialog --textbox "$temp_file" 20 70
    rm "$temp_file"
}

add_item(){
    name=$(dialog --inputbox "Enter item name:" 10 40 3>&1 1>&2 2>&3 3>&-)
    price=$(dialog --inputbox "Enter item price:" 10 40 3>&1 1>&2 2>&3 3>&-)
    qty=$(dialog --inputbox "Enter quantity available:" 10 40 3>&1 1>&2 2>&3 3>&-)
    $MYSQL "INSERT INTO items(name, price, quantity) VALUES('$name', $price, $qty);"
    dialog --msgbox "Item added successfully!" 6 40
}

view_item(){
    temp_file=$(mktemp)
    echo "ID   | Name                 | Price     | Quantity" > "$temp_file"
    echo "-----|----------------------|-----------|----------" >> "$temp_file"
    $MYSQL "SELECT id, name, price, quantity FROM items;" | tail -n +2 | awk -F'\t' '{ printf "%-4s | %-20s | %-9s | %-8s\n", $1, $2, $3, $4 }' >> "$temp_file"
    dialog --textbox "$temp_file" 20 70
    rm "$temp_file"
}

edit_item(){
    id=$(dialog --inputbox "Enter item ID to edit:" 10 40 3>&1 1>&2 2>&3 3>&-)
    name=$(dialog --inputbox "Enter new item name:" 10 40 3>&1 1>&2 2>&3 3>&-)
    price=$(dialog --inputbox "Enter new price:" 10 40 3>&1 1>&2 2>&3 3>&-)
    qty=$(dialog --inputbox "Enter new quantity:" 10 40 3>&1 1>&2 2>&3 3>&-)
    $MYSQL "UPDATE items SET name='$name', price=$price, quantity=$qty WHERE id=$id;"
    dialog --msgbox "Item updated successfully!" 6 40
}

delete_item(){
    id=$(dialog --inputbox "Enter item ID to delete (only if quantity = 0):" 10 40 3>&1 1>&2 2>&3 3>&-)
    qty=$($MYSQL "SELECT quantity FROM items WHERE id = $id;" | tail -n 1)
    if [[ "$qty" == "0" ]]; then
        $MYSQL "DELETE FROM items WHERE id=$id;"
        dialog --msgbox "Item deleted successfully." 6 40
    else
        dialog --msgbox "Cannot delete. Quantity is not zero." 6 50
    fi
}

create_bill(){
    cust_id=$(dialog --inputbox "Enter customer ID:" 10 40 3>&1 1>&2 2>&3 3>&-)
    now=$(date '+%Y-%m-%d %H:%M:%S')
    $MYSQL "INSERT INTO bills(customer_id, total, date) VALUES($cust_id, 0, '$now');"
    bill_id=$($MYSQL "SELECT MAX(id) FROM bills;" | tail -n 1)
    total=0
    sr=1
    bill_file=$(mktemp)
    echo "                    DELICIOUS BITE            " >> "$bill_file"
    echo "-----------------------------------------------" >> "$bill_file"
    echo "Bill ID: $bill_id" >> "$bill_file"
    echo "Date: $now" >> "$bill_file"
    echo "" >> "$bill_file"
    echo "S.No | Item            | Qty | Price | Subtotal" >> "$bill_file"
    echo "-----|-----------------|-----|-------|---------" >> "$bill_file"

    while true; do
        item_id=$(dialog --inputbox "Enter item ID (0 to finish):" 10 40 3>&1 1>&2 2>&3 3>&-)
        [[ "$item_id" == "0" ]] && break
        qty=$(dialog --inputbox "Enter quantity:" 10 40 3>&1 1>&2 2>&3 3>&-)
        price=$($MYSQL "SELECT price FROM items WHERE id=$item_id;" | tail -n 1)
        name=$($MYSQL "SELECT name FROM items WHERE id=$item_id;" | tail -n 1)
        subtotal=$(echo "$price * $qty" | bc -l)
        total=$(echo "$total + $subtotal" | bc -l)
        printf "%-5s | %-15s | %-3s | %-6s | %-8.2f\n" "$sr" "$name" "$qty" "$price" "$subtotal" >> "$bill_file"
        sr=$((sr+1))
        $MYSQL "INSERT INTO bill_items VALUES($bill_id, $item_id, $qty);"
    done

    $MYSQL "UPDATE bills SET total=$total WHERE id=$bill_id;"
    echo "-----------------------------------------------" >> "$bill_file"
    echo "Total: ₹$total" >> "$bill_file"
    dialog --textbox "$bill_file" 22 70
    rm "$bill_file"
}

view_bills(){
    temp_file=$(mktemp)
    echo "ID   | Customer Name         | Total     | Date         | Time" > "$temp_file"
    echo "-----|------------------------|-----------|--------------|--------" >> "$temp_file"
    $MYSQL "SELECT CONCAT(LPAD(b.id, 5, ' '), ' | ', LPAD(c.name, 20, ' '), ' | ₹', LPAD(b.total, 9, ' '), ' | ', LPAD(DATE(b.date), 12, ' '), ' | ', LPAD(TIME(b.date), 8, ' ')) FROM bills b JOIN customers c ON b.customer_id = c.id;" | tail -n +2 >> "$temp_file"
    dialog --textbox "$temp_file" 20 70
    rm "$temp_file"
}

view_bill_by_id(){
    bid=$(dialog --inputbox "Enter Bill ID:" 10 40 3>&1 1>&2 2>&3 3>&-)
    temp_file=$(mktemp)
    echo "                         DELICIOUS BITE                 " >> "$temp_file"
    echo "Bill ID: $bid" >> "$temp_file"
    echo "Item               | Qty | Price  | Subtotal" >> "$temp_file"
    echo "--------------------|-----|--------|----------" >> "$temp_file"
    $MYSQL "SELECT i.name, bi.quantity, i.price, (i.price * bi.quantity) FROM bill_items bi JOIN items i ON bi.item_id = i.id WHERE bi.bill_id = $bid;" | tail -n +2 | awk '{ printf "%-20s | %-3s | %-6s | %-8s\n", $1, $2, $3, $4 }' >> "$temp_file"
    total=$($MYSQL "SELECT total FROM bills WHERE id = $bid;" | tail -n 1)
    echo "-----------------------------------------" >> "$temp_file"
    echo "Total: ₹$total" >> "$temp_file"
    dialog --textbox "$temp_file" 20 70
    rm "$temp_file"
}

generate_daily_report(){
    today=$(date +%F)
    temp_file=$(mktemp)
    echo "ID   | Customer Name         | Total     | Time" > "$temp_file"
    echo "-----|------------------------|-----------|--------" >> "$temp_file"
    $MYSQL "SELECT CONCAT(LPAD(b.id, 5, ' '), ' | ', LPAD(c.name, 20, ' '), ' | ₹', LPAD(b.total, 9, ' '), ' | ', LPAD(TIME(b.date), 8, ' ')) FROM bills b JOIN customers c ON b.customer_id = c.id WHERE DATE(b.date) = '$today';" | tail -n +2 >> "$temp_file"
    dialog --textbox "$temp_file" 20 70
    rm "$temp_file"
}

# MAIN MENU
while true; do
    choice=$(dialog --clear --title "Billing Management Menu" \
        --menu "Choose an option:" 20 60 15 \
        1 "Add Customer" \
        2 "View Customers" \
        3 "Delete Customer" \
        4 "Add Item" \
        5 "View Items" \
        6 "Edit Item" \
        7 "Delete Item (if quantity = 0)" \
        8 "Create Bill" \
        9 "View All Bills" \
        10 "View Bill by ID" \
        11 "Generate Daily Report" \
        0 "Exit" \
        3>&1 1>&2 2>&3)

    case $choice in
        1) add_customer ;;
        2) view_customer ;;
        3) delete_customer ;;
        4) add_item ;;
        5) view_item ;;
        6) edit_item ;;
        7) delete_item ;;
        8) create_bill ;;
        9) view_bills ;;
        10) view_bill_by_id ;;
        11) generate_daily_report ;;
        0) break ;;
        *) dialog --msgbox "Invalid Option!" 6 30 ;;
    esac
done
