package cloudevents

import (
	"fmt"
	"github.com/carverauto/threadr/pkg/adapters/broker"
)

func CreateCloudEventsHandler(natsURL, subject, stream string, subscribe bool) (*broker.CloudEventsNATSHandler, error) {
	handler, err := broker.NewCloudEventsNATSHandler(natsURL, subject, stream, subscribe)
	if err != nil {
		return nil, fmt.Errorf("failed to create CloudEvents handler: %w", err)
	}
	return handler, nil
}
