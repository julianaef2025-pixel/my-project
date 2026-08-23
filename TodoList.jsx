import { useState } from "react";

const initialTodos = [
  { id: 1, name: "Вивчити основи React", completed: false },
  { id: 2, name: "Розібратися з React Router", completed: false },
  { id: 3, name: "Пережити Redux", completed: true },
];

export default function TodoList() {
  const [todos, setTodos] = useState(initialTodos);
  const [newName, setNewName] = useState("");
  const [filter, setFilter] = useState("");

  const handleCreate = (e) => {
    e.preventDefault();
    const name = newName.trim();
    if (!name) return;
    setTodos([...todos, { id: Date.now(), name, completed: false }]);
    setNewName("");
  };

  const toggleTodo = (id) => {
    setTodos(
      todos.map((todo) =>
        todo.id === id ? { ...todo, completed: !todo.completed } : todo
      )
    );
  };

  const deleteTodo = (id) => {
    setTodos(todos.filter((todo) => todo.id !== id));
  };

  const visibleTodos = todos.filter((todo) =>
    todo.name.toLowerCase().includes(filter.toLowerCase())
  );

  const completedCount = todos.filter((todo) => todo.completed).length;

  return (
    <div className="todo-page">
      <style>{`
        .todo-page {
          max-width: 640px;
          margin: 0 auto;
          padding: 24px 16px;
          font-family: Arial, Helvetica, sans-serif;
          color: #000;
          background: #fff;
        }

        .todo-stats p {
          margin: 2px 0;
          font-size: 15px;
        }

        .todo-form {
          margin-top: 48px;
          border: 1px solid #ccc;
          border-radius: 4px;
          padding: 16px;
        }

        .todo-form input {
          display: block;
          width: 95%;
          height: 60px;
          padding: 4px 8px;
          font-size: 16px;
          border: 1px solid #ccc;
          border-radius: 3px;
          box-sizing: border-box;
        }

        .todo-form button {
          margin-top: 16px;
          width: 200px;
          height: 40px;
          background: #2eb82e;
          color: #fff;
          font-size: 16px;
          border: none;
          border-radius: 3px;
          cursor: pointer;
        }

        .todo-form button:hover {
          background: #29a329;
        }

        .todo-filter {
          margin-top: 90px;
          display: flex;
          align-items: center;
          gap: 12px;
          font-size: 15px;
        }

        .todo-filter input {
          width: 250px;
          height: 26px;
          padding: 2px 6px;
          font-size: 15px;
          border: 1px solid #999;
          border-radius: 2px;
          box-sizing: border-box;
        }

        .todo-items {
          margin-top: 56px;
          list-style: none;
          padding: 0;
        }

        .todo-item {
          display: flex;
          align-items: center;
          border: 1px solid #ccc;
          padding: 14px 12px;
        }

        .todo-item + .todo-item {
          margin-top: 8px;
        }

        .todo-item input[type="checkbox"] {
          width: 16px;
          height: 16px;
          margin: 0;
          cursor: pointer;
        }

        .todo-item .todo-name {
          flex: 1;
          text-align: center;
          font-size: 15px;
        }

        .todo-item .todo-name.completed {
          text-decoration: line-through;
        }

        .todo-item button {
          width: 200px;
          height: 44px;
          background: #2eb82e;
          color: #fff;
          font-size: 16px;
          border: none;
          border-radius: 3px;
          cursor: pointer;
        }

        .todo-item button:hover {
          background: #29a329;
        }
      `}</style>

      <div className="todo-stats">
        <p>Вього завдань: {todos.length}</p>
        <p>Виконано: {completedCount}</p>
      </div>

      <form className="todo-form" onSubmit={handleCreate}>
        <input
          type="text"
          value={newName}
          onChange={(e) => setNewName(e.target.value)}
        />
        <button type="submit">Create</button>
      </form>

      <div className="todo-filter">
        <label htmlFor="todo-filter-input">Фільтр по імені</label>
        <input
          id="todo-filter-input"
          type="text"
          value={filter}
          onChange={(e) => setFilter(e.target.value)}
        />
      </div>

      <ul className="todo-items">
        {visibleTodos.map((todo) => (
          <li className="todo-item" key={todo.id}>
            <input
              type="checkbox"
              checked={todo.completed}
              onChange={() => toggleTodo(todo.id)}
            />
            <span className={`todo-name${todo.completed ? " completed" : ""}`}>
              {todo.name}
            </span>
            <button type="button" onClick={() => deleteTodo(todo.id)}>
              Delete
            </button>
          </li>
        ))}
      </ul>
    </div>
  );
}
