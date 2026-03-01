// Part 2: Create commerce.events collection and sample documents (user_id referenced)
// Run after MongoDB + replica set init: kubectl exec -it deploy/mongodb -n data-sources -- mongosh commerce --file /dev/stdin < scripts/mongodb-init-events.js
// Or: kubectl cp scripts/mongodb-init-events.js data-sources/$(kubectl get pod -n data-sources -l app=mongodb -o jsonpath='{.items[0].metadata.name}'):/tmp/init.js && kubectl exec -n data-sources deploy/mongodb -- mongosh commerce /tmp/init.js

db.createCollection("events");

db.events.insertMany([
  { user_id: 1, action: "login", timestamp: new Date(), metadata: { ip: "192.168.1.1" } },
  { user_id: 1, action: "page_view", timestamp: new Date(), metadata: { path: "/home" } },
  { user_id: 2, action: "login", timestamp: new Date(), metadata: {} },
  { user_id: 2, action: "add_to_cart", timestamp: new Date(), metadata: { product_id: "P001" } },
  { user_id: 3, action: "page_view", timestamp: new Date(), metadata: { path: "/products" } },
  { user_id: 1, action: "add_to_cart", timestamp: new Date(), metadata: { product_id: "P002" } },
  { user_id: 4, action: "login", timestamp: new Date(), metadata: {} }
]);

print("Inserted " + db.events.countDocuments() + " sample events.");
