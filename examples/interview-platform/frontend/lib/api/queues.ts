import { httpClient } from "./client";

export interface QueueStats {
    name: string;
    description: string;
    messagesInQueue: number;
    messagesProcessing: number;
    messagesCompleted: number;
    messagesFailed: number;
    averageProcessingTime: number;
    status: string;
    lastProcessed: string;
}

export interface QueueMessage {
    id: string;
    queueName: string;
    type: string;
    subject: string;
    priority: number;
    status: string;
    createdAt: string;
    processedAt?: string;
}

export const queuesApi = {
    listQueues: async (): Promise<QueueStats[]> => {
        const response = await httpClient.get("/api/queues");
        return response.data.data || [];
    },

    getQueueStats: async (queueName: string): Promise<QueueStats> => {
        const response = await httpClient.get(`/api/queues/${queueName}/stats`);
        return response.data.data;
    },

    getRecentMessages: async (): Promise<QueueMessage[]> => {
        const response = await httpClient.get("/api/queues/messages/recent");
        return response.data.data || [];
    },
};
