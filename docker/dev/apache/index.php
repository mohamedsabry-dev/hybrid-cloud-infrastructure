<?php
    $conn = pg_connect("host=" . getenv('DB_HOST') . " port=5432 dbname=" . getenv('DB_NAME') . " user=" . getenv('DB_USER') . " password=" . getenv('DB_PASS'));
    if (!$conn) {
        echo "DB connection failed";
        exit(1);
    }
    $result = pg_query($conn, "SELECT name, price FROM products");
    echo "<h1>Product List</h1>";
    echo "<table border='1'><tr><th>Name</th><th>Price</th></tr>";
    while ($row = pg_fetch_assoc($result)) {
        echo "<tr><td>{$row['name']}</td><td>\${$row['price']}</td></tr>";
    }
    echo "</table>";
    echo "<p>Served by: " . gethostname() . " on port " . getenv('APACHE_PORT') . "</p>"; 
    pg_close($conn);
?>