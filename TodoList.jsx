import { Component } from 'react';
import todosData from './todo.json';
import './TodoList.css';

class TodoList extends Component {
    state = {
        todos: todosData,
        newText: '',
        filter: '',
    };

    // form input
    handleNewTextChange = (e) => {
        this.setState({ newText: e.target.value });
    };

    // create new task
    handleSubmit = (e) => {
        e.preventDefault();
        const text = this.state.newText.trim();
        if (!text) return;

        const newTodo = {
            id: 'id-' + Date.now(),
            text: text,
            completed: false,
        };

        this.setState({
            todos: [...this.state.todos, newTodo],
            newText: '',
        });
    };

    // checkbox — toggle completed
    toggleTodo = (id) => {
        this.setState({
            todos: this.state.todos.map((todo) =>
                todo.id === id ? { ...todo, completed: !todo.completed } : todo
            ),
        });
    };

    // delete task
    deleteTodo = (id) => {
        this.setState({
            todos: this.state.todos.filter((todo) => todo.id !== id),
        });
    };

    // filter input
    handleFilterChange = (e) => {
        this.setState({ filter: e.target.value });
    };

    render() {
        const { todos, newText, filter } = this.state;

        const visibleTodos = todos.filter((todo) =>
            todo.text.toLowerCase().includes(filter.toLowerCase())
        );

        const completedCount = todos.filter((todo) => todo.completed).length;

        return (
            <div className="todo-page">
                <p>Вього завдань: {todos.length}</p>
                <p>Виконано: {completedCount}</p>

                <form className="todo-form" onSubmit={this.handleSubmit}>
                    <input
                        type="text"
                        value={newText}
                        onChange={this.handleNewTextChange}
                    />
                    <button type="submit">Create</button>
                </form>

                <div className="todo-filter">
                    <label>Фільтр по імені</label>
                    <input
                        type="text"
                        value={filter}
                        onChange={this.handleFilterChange}
                    />
                </div>

                <ul className="todo-items">
                    {visibleTodos.map((todo) => (
                        <li className="todo-item" key={todo.id}>
                            <input
                                type="checkbox"
                                checked={todo.completed}
                                onChange={() => this.toggleTodo(todo.id)}
                            />
                            <span className={todo.completed ? 'done' : ''}>
                                {todo.text}
                            </span>
                            <button onClick={() => this.deleteTodo(todo.id)}>
                                Delete
                            </button>
                        </li>
                    ))}
                </ul>
            </div>
        );
    }
}

export default TodoList;
