import Foundation

/// Yaad, dadi's memory: the planner's plans and tasks, and the two things this
/// app writes to it, a task ticked and whether Ankur attended a plan.
struct YaadClient: Sendable {
    /// Yaad's address on dadi, served by Caddy on the box.
    static let baseURL = URL(string: "http://yaad.dadi")!

    let client: ServiceClient

    init(session: URLSession) {
        client = ServiceClient(session: session, baseURL: Self.baseURL)
    }

    /// POST /planner/plans: every plan touching [from, to), earliest first, declined ones included. What each
    /// view draws of them is `PlanFilter`'s to say.
    func plans(from: Date, to: Date) async throws -> [Plan] {
        struct Response: Decodable { let items: [Plan] }
        let response: Response = try await client.post("/planner/plans", body: PlansQuery(from: from, to: to))
        return response.items
    }

    /// POST /planner/tasks: what the checklist holds for the local day `key` (YYYY-MM-DD).
    func tasks(on key: String) async throws -> [PlanTask] {
        try await tasks(.day(key))
    }

    /// The Someday tasks: those Yaad holds with no window, and any of today's list with no close, each once.
    func somedayTasks() async throws -> [PlanTask] {
        async let windowless = tasks(.someday)
        async let dated = tasks(on: TaskLogic.key(.now))
        return try await TaskLogic.someday(windowless + dated)
    }

    /// POST /planner/tasks for each of `days` at once: every day's checklist, by its YYYY-MM-DD key.
    func taskLists(for days: [Date], calendar: Calendar = .current) async throws -> [String: [PlanTask]] {
        try await withThrowingTaskGroup(of: (String, [PlanTask]).self) { group in
            for day in days {
                let key = TaskLogic.key(day, calendar: calendar)
                group.addTask { (key, try await tasks(on: key)) }
            }
            var lists: [String: [PlanTask]] = [:]
            for try await (key, tasks) in group { lists[key] = tasks }
            return lists
        }
    }

    private func tasks(_ query: TasksQuery) async throws -> [PlanTask] {
        struct Response: Decodable { let items: [PlanTask] }
        let response: Response = try await client.post("/planner/tasks", body: query)
        return response.items
    }

    /// PUT /planner/tasks/done: ticks the task, or takes the tick back.
    func setDone(_ done: Bool, task: String) async throws -> TaskDoneResponse {
        try await client.put("/planner/tasks/done", body: TaskDoneRequest(taskId: task, done: done))
    }

    /// PUT /planner/plans/attended: records whether Ankur was at the plan; nil clears it.
    func setAttended(_ attended: Bool?, plan: String) async throws -> AttendedResponse {
        try await client.put("/planner/plans/attended", body: AttendedRequest(planId: plan, attended: attended))
    }

    /// GET /counts: how many nodes Yaad keeps, in total and by kind.
    func counts() async throws -> YaadCounts {
        try await client.get("/counts")
    }

    /// GET /events: one element per write to Yaad's plans or memories.
    func changes() async throws -> AsyncThrowingStream<Void, Error> {
        try await client.changes("/events")
    }
}
