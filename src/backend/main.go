package main

import (
    "context"
    "fmt"
    "log"
    "net/http"
    "os"
    "time"
    "encoding/json"
    "go.mongodb.org/mongo-driver/bson"
    "go.mongodb.org/mongo-driver/mongo"
    "go.mongodb.org/mongo-driver/mongo/options"
)

var collection *mongo.Collection

type Counter struct {
    ID    string `bson:"_id"`
    Count int    `bson:"count"`
}

func main() {
    // Read MongoDB connection string from Vault-injected file
    uriBytes, err := os.ReadFile("/vault/secrets/db-creds.txt")
    if err != nil {
        log.Fatalf("Failed to read Mongo URI from file: %v", err)
    }
    uri := string(uriBytes)

    // Connect to MongoDB
    ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
    defer cancel()
    client, err := mongo.Connect(ctx, options.Client().ApplyURI(uri))
    if err != nil {
        log.Fatalf("Mongo connect error: %v", err)
    }
    if err = client.Ping(ctx, nil); err != nil {
        log.Fatalf("Mongo ping error: %v", err)
    }

    db := client.Database("mydb") // Database name as per connection URI
    collection = db.Collection("visits") // Collection to store visit count

    http.HandleFunc("/api/ping", pingHandler)
    log.Println("Backend server is running on port 8080...")
    log.Fatal(http.ListenAndServe(":8080", nil))
}

func pingHandler(w http.ResponseWriter, r *http.Request) {
    if r.Method != http.MethodGet {
        http.Error(w, "Invalid method", http.StatusMethodNotAllowed)
        return
    }

    ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
    defer cancel()

    // Atomically increment the counter document in MongoDB
    opts := options.FindOneAndUpdate().SetUpsert(true).SetReturnDocument(options.After)
    result := collection.FindOneAndUpdate(ctx,
        bson.M{"_id": "counter"},
        bson.M{"$inc": bson.M{"count": 1}},
        opts,
    )
    if result.Err() != nil {
        log.Printf("DB update error: %v", result.Err())
        http.Error(w, "Database error", http.StatusInternalServerError)
        return
    }

    var counter Counter
    if err := result.Decode(&counter); err != nil {
        log.Printf("DB decode error: %v", err)
    }

    msg := fmt.Sprintf("Hello, you are visitor #%d", counter.Count)
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(map[string]string{"message": msg})
} 